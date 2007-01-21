#!/usr/bin/perl
# $Id$

die(
	"* For consistency, on_init(), aka init(), is called in the new\n",
	"* object's context rather than the creator's context.  Therefore\n",
	"* it cannot successfully create requests on the creator's behalf.\n",
	"* Self-requesting stages may be brought back in the future, but\n",
	"* they currently do not work.\n",
);

# Create a very simple stage that performs a task and returns a
# mesage.  The magic here is that the stage makes its own request in
# init() so the creator isn't required to go through the two-step
# create/request dance.

{
	package SelfRequester;
	use POE::Stage qw(:base self);
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

	sub init :Handler {
		my $args = $_[1];

		warn 0;
		my $passthrough_args = delete $args->{args} || {};
		my $self_auto_request = POE::Request->new(
			stage   => self,
			method  => "set_thingy",
			%$args,
			args    => { %$passthrough_args },
		);
	}

	sub set_thingy :Handler {
		my $arg_seconds;
		warn 1;

		my $req_delay = POE::Watcher::Delay->new(
			seconds     => $arg_seconds,
			on_success  => "time_is_up",
		);
	}

	sub time_is_up :Handler {
		my $self_auto_request;
		warn 2;
		$self_auto_request->return(
			type => "done",
		);

		# Don't need to delete these as long as the request is canceled,
		# either by calling req->return() on ->cancel().
		#$self_auto_request = undef;
		#my $req_delay = undef;
	}
}

{
	package App;
	use POE::Stage::App qw(:base self);

	sub on_run {
		warn 3;
		self->spawn_requester();
	}

	sub do_again {
		warn 4;
		self->spawn_requester();
	}

	sub spawn_requester {
		warn 5;

		my $req_requester = SelfRequester->new(
			on_done   => "do_again",
			args      => {
				seconds => 0.001,
			},
		);
	}
}

package main;

App->new()->run();
exit;
