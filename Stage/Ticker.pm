# $Id$

# A sample Stage that emits multiple messages for a single request.
# This is the same pattern as POE::Component::IRC uses.

package Stage::Ticker;

use warnings;
use strict;

# We call components "Stages".  A complex task may be performend in a
# number of stages, each of which requesting from others that work be
# done.

use base qw(Stage);

# Pow! Zing! Wham! Poit!

use Pow::Delay;

# A lot of methods are probably synchronous, so :sync is the default.
# It needn't be specified.

# One could generally assume that inter-object calls are asynchronous,
# and intra-object calls synchronous.  That would be a false
# assumption, however.  It's often necessary to synchronously call
# across objects for such things as accessors.
#
# It should probably be a constraint of the system that one cannot
# synchronously call across process boundaries.  Not at least without
# threads.

# init() is internally called by Stage as post-constructor
# initialization.  Synchronously.  It should be an error to specify it
# asynchronous.

sub init {
	my ($self, $call) = @_;
	# XXX - Do we need to do anything here?
}

# Accept the request to start ticking.  This is asynchronous.  It's
# meant to be invoked by other objects.

sub start_ticking :async {
	my ($self, $call) = @_;

	# Members with leading underscores are scoped to the current
	# request.  When $call's lifetime ends, so does the request and all
	# its contents.

	# Since a single request can generate many ticks, keep a counter so
	# we can tell one from another.
	$self->{_tick_id} = 0;

	# I forget what "Pow" means or stands for.  Anyway, Pow classes are
	# resources or event generators.
	# 1. They have the capability of throwing events throughout their
	# lifetimes.
	# 2. They keep alive the contexts that were active during their
	# creation.
	# 3. They throw events back to their creators within the same
	# context that was active during their creation.
	# 4. The active context keeps alive the hidden POE::Session that
	# drives the Stage.

	$self->{_delay} = Pow::Delay->new(
		length => $call->{interval},
		method => "got_tick",
	);
}

# We've received a tick from an internal Paw::Delay object.
# All Pow:: callbacks within a Stage should be synchronous.
# We should throw an error if a handler was set :async.

sub got_tick {
	my ($self, $call) = @_;

	# The $call object is in the same context as the one in
	# start_ticker(), but its values are those passed in from
	# Paw::Delay.  Therefore $call->emit() passes a value back to the
	# Stage that initiated the request.

	# Meanwhile, we're still within the same context as the request that
	# was passed into start_ticker(), so $self->{_tick_id} exists within
	# that scope.  To reiterate, each request has its own scope with its
	# own _tick_id and _delay.
#warn "got tick ($self, $call)";
	$call->emit(
		type => "tick",
		id   => ++$self->{_tick_id},
	);

	# End the request and clean up if we've thrown enough ticks.  This
	# is a bailout for testing purposes.

	return $call->end() if $self->{_tick_id} >= 10;

	# Otherwise throw another delay.  Since the object's still around,
	# we can theoretically tell it to start again.

	# TODO - Ideally, again() should exist.  Meanwhile, create a new
	# delay.

	# $self->{_delay}->again();
	$self->{_delay} = Pow::Delay->new(
		length => $call->{interval},
		method => "got_tick",
	);
}

1;
