#!/sw/bin/env perl
# $Id$

use lib qw(../lib);

# Prototype of a Moose-based POE::Stage.  It is functional but not
# functionally complete.  It doesn't represent any features from
# POE::Stage.  It's hoped that this may become the new interface and
# framework for POE::Stage's next overhaul, but there are no
# guarantees.

{ package Namespace;
	use Moose;

	# Namespace is a local representation of a global registry of
	# objects and their roles, or something.  Erlang and Scala call this
	# a Node.
	#
	# When a program attaches to a network, it acquires a copy of the
	# network's object registry so that it can pass messages to remote
	# objects.

	has local_actors => (
		is => 'rw',
		isa => 'HashRef[Actor]',
		default => sub { {} },
		metaclass => 'Collection::Hash',
		provides => {
			count => 'has_local_actor',
			delete => '_remove',
			set => '_add',
		},
	);

	sub add_actor {
		my ($self, $actor) = @_;
		$self->_add($actor->id(), $actor);
	}
}

{ package Message;
	use Moose;

	has type => (
		is => 'rw',
		isa => 'Str',
	);

	has target => (
		is => 'ro',
		isa => 'Object',
	);

	has args => (
		is => 'ro',
		isa => 'HashRef[Any]',
	);

	has sender => (
		is => 'ro',
		isa => 'Str',
	);

	has context => (
		is => 'rw',
		isa => 'HashRef[Any]',
	);

	has dispatcher => (
		is => 'rw',
		isa => 'Dispatcher',
	);

	# TODO - Sender and target contexts should not be coupled to the
	# request.  Passing a request should not involve copying (or
	# serializing and transmitting) data the target will never see.
	#
	# A better mechanism would be to keep the sender context in the
	# reqest, but strip it from the copy transmitted down the wire.
	#
	# On the receiving end, the target can initialize its context before
	# initial dispatch.

	has sender_context => (
		is => 'rw',
		isa => 'HashRef[Any]',
		default => sub { {} },
	);

	has target_context => (
		is => 'rw',
		isa => 'HashRef[Any]',
		default => sub { {} },
	);

	sub juggle {
		my ($self, $arg) = @_;

		$self->type($arg->{type}) if $arg->{type};
		$self->dispatcher->send($self);
	}
}

{ package Call;
	use Moose;
	extends 'Message';

	# A Call is a particular kind of message.
}

{ package Event;
	use Moose;
}

{ package Event::Timeout;
	use Moose;
	extends 'Event';
}

{ package Event::Interrupted;
	use Moose;
	extends 'Event';
}

{ package EventGenerator;
	use Moose;
	use MooseX::AttributeHelpers;

	has pending_events => (
		is => 'rw',
		isa => 'ArrayRef[Event]',
		default => sub { [] },
		metaclass => 'Collection::Array',
		provides => {
			count => 'has_pending_event',
			shift => 'next_pending_event',
			push  => 'defer_event',
		},
	);

	has watchers => (
		is => 'rw',
		isa => 'HashRef[Watcher]',
		default => sub { {} },
		metaclass => 'Collection::Hash',
		provides => {
			count => 'has_watchers',
			get => 'get_watcher',
			delete => 'remove_watcher',
			set => 'add_watcher',
		},
	);

	sub get_next_event {
		my ($self, $arg) = @_;

		# Stop time.  Assuming we fall through below, we don't want to
		# include the minimal time it took.

		my $now = time();

		# A previous loop found something.  Return that.

		return $self->next_pending_event() if $self->has_pending_event();

		# How long are we allowed to wait for events?

		my $time_to_wait = $arg->{max_wait} || 0;
		$time_to_wait -= time() - $now;

		# Oops; we've been here too long.

		return Event::Timeout->new() if $time_to_wait <= 0;

		# If we have no watchers, simply sleep for the time being.

		unless ($self->has_watchers()) {
			sleep $time_to_wait;
			return Event::Interrupted->new() if $time_to_wait > time() - $now;
			return Event::Timeout->new();
		}

		# TODO - Actually check for events.
		die "actually check for events";
	}
}

{ package MessageQueue;
	use Moose;
	use MooseX::AttributeHelpers;

	has calls => (
		is => 'rw',
		isa => 'ArrayRef[Message]',
		default => sub { [] },
		metaclass => 'Collection::Array',
		provides => {
			shift => 'get_next_message',
			count => 'has_message',
			push => 'enqueue',
		},
	);
}

{ package Dispatcher;
	use Moose;

	has message_queue => (
		is => 'ro',
		isa => 'MessageQueue',
	);

	has event_generator => (
		is => 'rw',
		isa => 'EventGenerator',
	);

	has namespace => (
		is => 'rw',
		isa => 'Namespace',
	);

	sub run {
		my $self = shift;

		while ($self->namespace->has_local_actor()) {

			# Start by looking for events.

			my $event = $self->event_generator->get_next_event(
				{ max_wait => 0 }
			);

			# TODO - Handle event.

			# Dispatch pending messages.

			my $next_message = $self->message_queue->get_next_message();
			last unless defined $next_message;

			my $target_object = $next_message->target();
			my $message_type = $next_message->type();

			# TODO - Translate the message type into a method.  For now
			# we're asuming the message type is a method name.  Later we
			# should consult the target object for a type/method mapping.

			$next_message->context( $next_message->target_context() );
			$target_object->$message_type($next_message);
			$next_message->context( $next_message->sender_context() );

			# TODO - Time for the actor to die?
		}
	}

	sub send {
		my ($self, $message) = @_;

		# TODO - Currently we just drop the message into the queue.
		# Ultimately we should consult the namespace for the target's real
		# location.  If the target's on another process, we should queue
		# the message for delivery there.

		$message->dispatcher($self);
		$self->message_queue->enqueue($message);
	}

	# TODO - How can we assimilate the add_actor method of our
	# namespace, as if it were a mix-in?  Would that be bad form?

	sub add_actor {
		my ($self, $actor) = @_;
		$self->namespace->add_actor($actor);
	}
}

{ package Actor;
	use Moose;
	use Time::HiRes qw(time);
	use Sys::Hostname;

	has id => (
		isa => 'Str',
		is => 'ro',
		default => sub { hostname() . " " . $$ . " " . time() },
	);

	has mailbox => (
		is => 'rw',
		isa => 'MessageQueue',
	);
}

{ package Actor::Forked;
	use Moose;
	extends 'Actor';

	# TODO - Fork and set up IPC with the parent.
	# Receive messages over IPC.
	# Send responses over IPC.
}

{ package App;
	use Moose;
	extends 'Actor';

	sub say_hello {
		my ($self, $message) = @_;
		my $whom = $message->args->{whom};
		my $count = ++$message->context->{count};

		print "hello, $whom! ($count)\n";

		if ($count < 9) {
			$message->juggle();
			return;
		}

		$message->juggle(
			{
				type => "say_goodbye",
			}
		);
	}

	sub say_goodbye {
		my ($self, $message) = @_;
		my $whom = $message->args->{whom};

		print "goodbye, $whom!\n";
	}
}

{ package main;

	my $dispatcher = Dispatcher->new(
		event_generator => EventGenerator->new(),
		message_queue => MessageQueue->new(),
		namespace => Namespace->new(),
	);

	my $app = App->new();
	$dispatcher->add_actor($app);

	my $request = Call->new(
		{
			type => "say_hello",
			args => { whom => "world", count => 0 },
			target => $app,
		},
	);
	$dispatcher->send($request);

	$dispatcher->run();
	exit;
}
