#!/sw/bin/env perl
# $Id$

# Small prototype of a Moose-based POE::Stage.  It is functional but
# not functionally complete.  It doesn't represent any features from
# POE::Stage.  It's hoped that this may become the new interface and
# framework for POE::Stage's next overhaul, but there are no
# guarantees.

{ package Namespace;
	use Moose;

	# TODO - Global registry of objects and their roles.
	# May be distributed across a network.
	# Message routing will be determined here.

	has space => (
		is => 'rw',
		isa => 'HashRef[Object]',
	);
}

{ package Call;
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

{ package Dispatcher;
	use Moose;

	# TODO - A quick and dirty push/shift queue.  This is a prototype to
	# be replaced by POE.

	has queue => (
		is => 'rw',
		isa => 'ArrayRef[Call]',
		default => sub { [] },
	);

	sub run {
		my $self = shift;

		while (1) {
			my $next_message = shift @{$self->queue()};
			last unless defined $next_message;

			my $target_object = $next_message->target();
			my $message_type = $next_message->type();

			# TODO - Translate the message type into a method.  For now
			# we're asuming the message type is a method name.  Later we
			# should consult the target object for a type/method mapping.

			$next_message->context( $next_message->target_context() );
			$target_object->$message_type($next_message);
			$next_message->context( $next_message->sender_context() );
		}
	}

	sub send {
		my ($self, $message) = @_;

		# TODO - Currently we just drop the message into the queue.
		# Ultimately we should consult the namespace for the target's real
		# location.  If the target's on another process, we should queue
		# the message for delivery there.

		$message->dispatcher($self);
		push @{$self->queue()}, $message;
	}
}

{ package App;
	use Moose;

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
	my $dispatcher = Dispatcher->new();
	my $app = App->new();

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
