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
	use POE::Stage qw(self);
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
		my $args = $_[1];

		warn 0;
		my $passthrough_args = delete $args->{args} || {};
		my $auto_request :Self = POE::Request->new(
			stage   => self,
			method  => "set_thingy",
			%$args,
			args    => { %$passthrough_args },
		);
	}

	sub set_thingy {
		my $seconds :Arg;
		warn 1;

		my $delay :Req = POE::Watcher::Delay->new(
			seconds     => $seconds,
			on_success  => "time_is_up",
		);
	}

	sub time_is_up {
		my $auto_request :Self;
		warn 2;
		$auto_request->return(
			type => "done",
		);

		# Don't need to delete these as long as the request is canceled,
		# either by calling req->return() on ->cancel().
		#delete $self->{request};
		#my $delay :Req = undef;
	}
}

{
	package App;
	use warnings;
	use strict;
	use POE::Stage qw(self);
	use base qw(POE::Stage);

	sub run {
		warn 3;
		self->spawn_requester();
	}

	sub do_again {
		warn 4;
		self->spawn_requester();
	}

	sub spawn_requester {
		warn 5;

		my $self_requester :Req = SelfRequester->new(
			on_done   => "do_again",
			args      => {
				seconds => 0.001,
			},
		);
	}
}

package main;
use warnings;
use strict;

my $app = App->new();
my $req = POE::Request->new(
	stage   => $app,
	method  => "run",
);

# Trap SIGINT and make it exit gracefully.  Problems in destructor
# timing will become apparent when warnings in them say "during global
# destruction."

$SIG{INT} = sub { warn "sigint"; exit };

POE::Kernel->run();
exit;
