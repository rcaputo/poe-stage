# $Id$

=head1 NAME

POE::Watcher::Delay - a class encapsulating the wait for elapsed time

=head1 SYNOPSIS

	# Note, this is not a complete program.
	# See the distribution's examples directory.

	# Request a delay notification.
	$self->{req}{watcher} = POE::Watcher::Delay->new(
		_length     => 10,            # wait 10 seconds, then
		_on_success => "time_is_up",  # call $self->time_is_up()
		param_1     => 123,           # with $args->{param_1}
		param_2     => "abc",         # and $args->{param_2}
	);

	# Handle the delay notification.
	sub time_is_up {
		my ($self, $args) = @_;
		print "$args->{param_1}\n";   # 123
		print "$args->{param_2}\n";   # abc
		delete $self->{req}{watcher}; # Destroy the watcher.
	}

=head1 DESCRIPTION

A POE::Watcher::Delay object waits a certain amount of time before
invoking a method on the current Stage object.  Both the time to wait
and the method to invoke are given as parameters to
POE::Watcher::Delay's constructor.  Additional parameters are passed
through the watcher to the method to invoke after the specified time
has elapsed.

=cut

package POE::Watcher::Delay;

use warnings;
use strict;

use Scalar::Util qw(weaken);
use Carp qw(croak);
use POE::Kernel;

=head2 new _length => SECONDS, _on_success => METHOD_NAME

Construct a new POE::Watcher::Delay.  The constructor takes two
parameters: _length is the length of time to wait, in seconds;
_on_success is the name of a method in the current Stage to call when
_length seconds have elapsed.

As with all POE::Watcher objects, constructor parameters that are not
adorned with leading underscores are passed unchanged to callbacks.

=cut

sub new {
	my ($class, %args) = @_;

	my $length = delete $args{_length};
	croak "$class requires a '_length' parameter" unless defined $length;

	my $on_success = delete $args{_on_success};
	croak "$class requires an '_on_success' method" unless defined $on_success;

	my $request = POE::Request->_get_current_request();
	croak "Can't create a $class without an active request" unless $request;

	# TODO - Make sure no other adorned arguments exist.

	# Wrap a weak copy of the request reference in a strong envelope so
	# it can be passed around.

	my $req_envelope = [ $request ];
	weaken $req_envelope->[0];

	my $self = bless {
		request     => $req_envelope,
		on_success  => $on_success,
		args        => \%args,
	}, $class;

	# Post out a timer.
	# Wrap a weak $self in a strong envelope for passing around.

	my $self_envelope = [ $self ];
	weaken $self_envelope->[0];

	$self->{delay_id} = $poe_kernel->delay_set(
		stage_timer => $length, $self_envelope
	);

	# Owner gets a strong reference.
	return $self;
}

sub DESTROY {
	my $self = shift;

	if (exists $self->{delay_id}) {
		$poe_kernel->alarm_remove(delete $self->{delay_id});
	}
}

# Resource delivery redelivers the request the resource was created
# in, but to a new method.
# TODO - Rename to _deliver, since this is an internal method.

sub deliver {
	my ($self, %args) = @_;

	# Open the envelope.
	my $request = $self->{request}[0];
	$request->deliver($self->{on_success});
}

1;

=head1 SEE ALSO

POE::Watcher describes concepts that are common to all POE::Watcher
classes.  It's required reading in order to understand fully what's
going on.

=head1 AUTHORS

Rocco Caputo <rcaputo@cpan.org>.

=head1 LICENSE

POE::Watcher::Delay is Copyright 2005 by Rocco Caputo.  All rights are
reserved.  You may use, modify, and/or distribute this module under
the same terms as Perl itself.

=cut
