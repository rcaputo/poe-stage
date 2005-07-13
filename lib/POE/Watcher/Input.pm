# $Id$

=head1 NAME

POE::Watcher::Input - watch a socket or other handle for input readiness

=head1 SYNOPSIS

	# Note, this is not a complete program.
	# See the distribution's examples directory.

	# Request a delay notification.
	$self->{req}{socket} = $socket_handle;
	$self->{req}{input} = POE::Watcher::Input->new(
		_handle   => $self->{req}{socket},
		_on_input => "read_from_socket",
	);

	# Handle the delay notification.
	sub read_from_socket {
		my ($self, $args) = @_;
		my $octets = sysread($self->{req}{handle}, my $buf = "", 65536);
		...;
	}

=head1 DESCRIPTION

POE::Watcher::Input watches a socket or other handle and delivers a
message whenever the handle becomes ready for reading.  Bot the handle
and the method to call are passed to POE::Watcher::Input objects at
construction time.

=cut

package POE::Watcher::Input;

use warnings;
use strict;

use Scalar::Util qw(weaken);
use Carp qw(croak);
use POE::Kernel;

=head2 new _handle => HANDLE, _on_input => METHOD_NAME

Begin waiting for data to arrive on a socket or other HANDLE.  When
the handle becomes ready for reading, alert the watcher's creator
stage by calling its METHOD_NAME method.

=cut

sub new {
	my ($class, %args) = @_;

	my $handle = delete $args{_handle};
	croak "$class requires a '_handle'" unless defined $handle;

	my $input_method = delete $args{_on_input};
	croak "$class requires an '_on_input'" unless defined $input_method;

	my $request = POE::Request->_get_current_request();
	croak "Can't create a $class without an active request" unless $request;

	# TODO - Make sure no other adorned arguments exist.

	# Wrap a weak copy of the request reference in a strong envelope so
	# it can be passed around.

	my $req_envelope = [ $request ];
	weaken $req_envelope->[0];

	my $self = bless {
		request   => $req_envelope,
		on_input  => $input_method,
		handle    => $handle,
		args      => \%args,
	}, $class;

	# Wrap a weak $self in a strong envelope for passing around.

	my $self_envelope = [ $self ];
	weaken $self_envelope->[0];

	$poe_kernel->select_read($handle, "stage_io", $self_envelope);

	# Owner gets a strong reference.
	return $self;
}

sub DESTROY {
	my $self = shift;

	if (exists $self->{handle}) {
		$poe_kernel->select_read(delete($self->{handle}), undef);
	}
}

# Resource delivery redelivers the request the resource was created
# in, but to a new method.

sub deliver {
	my ($self, %args) = @_;

	# Open the envelope.
	my $request = $self->{request}[0];
	$request->deliver($self->{on_input});
}

1;

=head1 BUGS

The watcher seems overly simple.  It probably has a large number of
nasty edge cases in its design.

=head1 SEE ALSO

POE::Watcher describes concepts that are common to all POE::Watcher
classes.  It's required reading in order to understand fully what's
going on.

=head1 AUTHORS

Rocco Caputo <rcaputo@cpan.org>.

=head1 LICENSE

POE::Watcher::Input is Copyright 2005 by Rocco Caputo.  All rights are
reserved.  You may use, modify, and/or distribute this module under
the same terms as Perl itself.

=cut
