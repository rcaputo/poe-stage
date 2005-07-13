# $Id$

=head1 NAME

POE::Stage::Receiver - a simple UDP recv/send component with a lousy name

=head1 SYNOPSIS

	# Note, this is not a complete program.
	# See the distribution's examples directory.

	use POE::Stage::Receiver;
	my $stage = POE::Stage::Receiver->new();
	my $request = POE::Request->new(
		_stage          => $stage,
		_method         => "listen",
		bind_port       => 8675,
		_on_datagram    => "handle_datagram",
		_on_recv_error  => "handle_error",
		_on_send_error  => "handle_error",
	);

	# Echo the datagram back to its sender.
	sub handle_datagram {
		my ($self, $args) = @_;
		$self->{rsp}->recall(
			_method        => "send",
			remote_address => $args->{remote_address},
			datagram       => $args->{datagram},
		);
	}

=head1 DESCRIPTION

POE::Stage::Receiver is a simple UDP receiver/sender stage.  Not only
is it easy to use, but it also rides the short bus for now.

Receiver has two public methods: listen() and send().  It emits a
small number of message types: datagram, recv_error, and send_error.

=cut

package POE::Stage::Receiver;

use warnings;
use strict;

use base qw(POE::Stage);

use POE::Watcher::Input;
use IO::Socket::INET;
use constant DATAGRAM_MAXLEN => 1024;

=head2 listen bind_port => INTEGER

Bind to a port on all local interfaces and begin listening for
datagrams.  The listen request should also map POE::Stage::Receiver's
message types to appropriate handlers.

=cut

sub listen {
	my ($self, $args) = @_;

	$self->{req}{bind_port} = delete $args->{bind_port};

	$self->{req}{socket} = IO::Socket::INET->new(
		Proto     => 'udp',
		LocalPort => $self->{req}{bind_port},
	);
	die "Can't create UDP socket: $!" unless $self->{req}{socket};

	$self->{req}{udp_watcher} = POE::Watcher::Input->new(
		_handle   => $self->{req}{socket},
		_on_input => "handle_input"
	);
}

sub handle_input {
	my ($self, $args) = @_;

	my $remote_address = recv(
		$self->{req}{socket},
		my $datagram = "",
		DATAGRAM_MAXLEN,
		0
	);

	if (defined $remote_address) {
		$self->{req}->emit(
			_type           => "datagram",
			datagram        => $datagram,
			remote_address  => $remote_address,
		);
	}
	else {
		$self->{req}->emit(
			_type => "recv_error",
			errnum => $!+0,
			errstr => "$!",
		);
	}
}

=head2 send datagram => SCALAR, remote_address => ADDRESS

Send a datagram to a remote address.  Usually called via recall() to
respond to a datagram emitted by the Receiver.

=cut

sub send {
	my ($self, $args) = @_;

	return if send(
		$self->{req}{socket},
		$args->{datagram},
		0,
		$args->{remote_address},
	) == length($args->{datagram});

	$self->{req}->emit(
		_type => "send_error",
		errnum => $!+0,
		errstr => "$!",
	);
}

1;

=head2 The "datagram" message.

POE::Stage::Receiver emits a message of "datagram" type whenever it
successfully recv()s a datagram.  The datagram message includes two
parameters: datagram contains the received data; remote_address
cantains the address that sent the datagram.

Both parameters can be pased back to the receiver's send() method, as
is done in the SYNOPSIS.

=head2 The error messages.

Both "recv_error" and "send_error" message types are virtually the
same.  They contain an errnum parameter with the numeric value of $!
just after the failure, and an errstr parameter with $!'s string
value.

=head1 BUGS

I'm wearying of documenting, so it's getting terser as I go along.

=head1 SEE ALSO

POE::Stage and POE::Request.  The examples/udp-peer.perl program in
POE::Stage's distribution.

=head1 AUTHORS

Rocco Caputo <rcaputo@cpan.org>.

=head1 LICENSE

POE::Stage::Receiver is Copyright 2005 by Rocco Caputo.  All rights
are reserved.  You may use, modify, and/or distribute this module
under the same terms as Perl itself.

=cut
