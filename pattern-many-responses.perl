#!/usr/bin/perl
# $Id$

# Illustrate the pattern of many responses for one request.

use warnings;
use strict;

use POE;
use Stage;
use Call;
use Pow::Delay;

{
	package Ticker;

	use warnings;
	use strict;

	use Stage;
	use Carp qw(croak);
	use POE::Session;

	sub spawn {
		my ($class, %arg) = @_;

		croak "Ticker needs an 'alias'" unless exists $arg{alias};

		Stage->create(
			inline_states => {
				_start => \&set_alias,
				start  => \&start_ticker,
				tick   => \&got_tick,
			},
			args => [ $arg{alias} ],
		);
	}

	sub set_alias {
		$_[KERNEL]->alias_set($_[ARG0]);
		$_[HEAP]->{tick_id} = 0;
	}

	sub start_ticker {
		my ($kernel, $heap, $call) = @_[KERNEL, HEAP, ARG0];

		# Passing $call as ARG1.  If it's passed as ARG0, Stage will call
		# receive() on it EVERY TIME IT'S PASSED.  That's bad because a
		# call can't be received twice.
		#
		# TODO - There must be a better way to track the "current" call
		# context.
		Pow::Delay->new(
			length => $call->arg("interval"),
			event  => "tick",
		);
	}

	sub got_tick {
		my ($kernel, $heap, $call) = @_[KERNEL, HEAP, ARG0];

		$call->emit(
			type => "tick",
			id   => ++$heap->{tick_id},
		);

		# Bailout for testing.
		return $call->cancel() if $heap->{tick_id} >= 10;

		Pow::Delay->new(
			length => $call->arg("interval"),
			event  => "tick",
		);
	}
}

### Main.

Ticker->spawn(alias => "tick");

Stage->create(
	inline_states => {
		_start => sub {

			# Create a Call to manage a single transaction between two
			# sessions.  Can be extended to work with components.

			my $c = Call->new(
				session  => "tick",
				event    => "start",
				interval => 1,
			);

			# Have the current session watch for a result on the Call.  This
			# example can be read as "On a return type of 'tick', send the
			# 'got_tick' event to the current session."

			$c->on(
				type     => "tick",
				event    => "got_tick",
			);

			# Send the Call on its way.

			$c->call();
		},

		got_tick => sub {
			my $call = $_[ARG0];
			print "tick: ", $call->arg("id"), "\n";
		},
	}
);

POE::Kernel->run();
exit;
