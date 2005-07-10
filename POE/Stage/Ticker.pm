# $Id$

# A sample POE::Stage that emits multiple messages for a single
# request.  This is the same pattern as POE::Component::IRC uses.

package POE::Stage::Ticker;

use warnings;
use strict;

use base qw(POE::Stage);

use POE::Watcher::Delay;

sub start_ticking {
	my ($self, $args) = @_;

	# Since a single request can generate many ticks, keep a counter so
	# we can tell one from another.

	$self->{req}{tick_id}  = 0;
	$self->{req}{interval} = $args->{interval};

	$self->set_delay();
}

sub got_watcher_tick {
	my ($self, $args) = @_;

	# Note: We have received two copies of the tick interval.  One is
	# from start_ticking() saving it in the request-scoped part of
	# $self.  The other is passed to us in $args, through the
	# POE::Watcher::Delay object.  We can use either one, but I thought
	# it would be nice for testing and illustrative purposes to make
	# sure they both agree.
	die unless $self->{req}{interval} == $args->{interval};

	$self->{req}->emit(
		_type => "tick",
		id   => ++$self->{req}{tick_id},
	);

	# TODO - Ideally we can restart the existing delay, perhaps with an
	# again() method.  Meanwhile we just create a new delay object to
	# replace the old one.

	$self->set_delay();
}

sub set_delay {
	my $self = shift;
	$self->{req}{delay} = POE::Watcher::Delay->new(
		_length     => $self->{req}{interval},
		_on_success => "got_watcher_tick",
		interval    => $self->{req}{interval},
	);
}

1;
