# $Id$

=head1 NAME

POE::Stage::Ticker - a periodic message generator for POE::Stage

=head1 SYNOPSIS

	$self->{req}{ticker} = POE::Stage::Ticker->new();
	$self->{req}{request} = POE::Request->new(
		_stage    => $self->{req}{ticker},
		_method   => "start_ticking",
		_on_tick  => "handle_tick",   # Invoke my handle_tick() method
		interval  => 10,              # every 10 seconds.
	);

	sub handle_tick {
		my ($self, $args) = @_;
		print "Handled tick number $args->{id} in a series.\n";
	}

=head1 DESCRIPTION

POE::Stage::Ticker emits recurring messages at a fixed interval.

=cut

package POE::Stage::Ticker;

use warnings;
use strict;

use base qw(POE::Stage);

use POE::Watcher::Delay;

=head1 PUBLIC COMMANDS

=head2 start_ticking (interval => FLOAT)

Used to request the Ticker to start ticking.  The Ticker will emit a
"tick" message every "interval" seconds.

=cut

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

=head1 PUBLIC RESPONSES

Responses are returned by POE::Request->return() or emit().

=head2 "tick" (id)

Once start_ticking() has been invoked, POE::Stage::Ticker emits a
"tick" event.  The "id" parameter is the ticker's unique ID, so that
ticks from multiple tickers are not confused.

=head1 BUGS

See http://thirdlobe.com/projects/poe-stage/report/1 for known issues.
See http://thirdlobe.com/projects/poe-stage/newticket to report one.

=head1 SEE ALSO

POE::Stage and POE::Request.  The examples/many-responses.perl program
in POE::Stage's distribution.

=head1 AUTHORS

Rocco Caputo <rcaputo@cpan.org>.

=head1 LICENSE

POE::Stage::Ticker is Copyright 2005 by Rocco Caputo.  All rights are
reserved.  You may use, modify, and/or distribute this module under
the same terms as Perl itself.

=cut
