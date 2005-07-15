#!/usr/bin/perl
# $Id$

# Create a very simple stage that performs a task and returns a
# mesage.  The magic here is that the stage makes its own request in
# init() so the creator isn't required to go through the two-step
# create/request dance.

{
	package SelfRequester;
	use warnings;
	use strict;
	use base qw(POE::Stage);
	use POE::Watcher::Delay;

	# My first try was to set a delay in init(), but the delay never
	# triggered time_is_up().  The program took the time to complete,
	# but the method didn't trigger.
	#
	# I think the rule is that you can't set Watchers from init()
	# because the current stage is that of the creator.  Or something.
	# My second attempt will be to fire a request and set the timer from
	# the method it triggers.
	#
	# The second attempt works.  I'm not sure I can force init() to be
	# executed within the new stage.  If it were, then the new request
	# here would be a child of that request, and it would probably
	# return() here instead of upstream one stage.
	#
	# TODO - Test that hypothesis.  I was pleasantly surprised when I
	# found out that init() could throw a request.  Maybe I will be
	# again, or the results will be close enough to make work without
	# too much ugliness.

	sub init {
		my ($self, $args) = @_;
		warn 0;
		$self->{request} = POE::Request->new(
			_stage => $self,
			_method => "set_thingy",
			%$args,
		);
	}

	sub set_thingy {
		my ($self, $args) = @_;
		warn 1;
		$self->{req}{delay} = POE::Watcher::Delay->new(
			_length     => $args->{length},
			_on_success => "time_is_up",
		);
	}

	# Another rule: One must delete a self-referential request and any
	# resources explicitly.  Both seem to hold strong circular
	# references, although I don't know exactly where.
	#
	# TODO - Find the strong circular references, and see which can be
	# weakened.

	sub time_is_up {
		my ($self, $args) = @_;
		warn 2;
		$self->{req}->return(
			_type => "done",
		);

		# Must delete these to break circular references.
		delete $self->{request};
		delete $self->{req}{delay};
	}
}

{
	package App;
	use warnings;
	use strict;
	use base qw(POE::Stage);

	sub run {
		my ($self, $args) = @_;
		warn 3;
		$self->spawn_requester();
	}

	sub do_again {
		my ($self, $args) = @_;
		warn 4;
		$self->spawn_requester();
	}

	sub spawn_requester {
		my $self = shift;
		warn 5;
		$self->{req}{self_requester} = SelfRequester->new(
			length   => 0.001,
			_on_done => "do_again",
		);
	}
}

package main;
use warnings;
use strict;

my $app = App->new();
my $req = POE::Request->new(
	_stage  => $app,
	_method => "run",
);

# Trap SIGINT and make it exit gracefully.  Problems in destructor
# timing will become apparent when warnings in them say "during global
# destruction."

$SIG{INT} = sub { warn "sigint"; exit };

POE::Kernel->run();
exit;
