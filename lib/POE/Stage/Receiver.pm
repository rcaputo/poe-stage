# $Id$

# A simple UDP recv/send kind of component.  It has a lousy name.

package POE::Stage::Receiver;

use warnings;
use strict;

use base qw(POE::Stage);

use POE::Watcher::Input;
use IO::Socket::INET;
use constant DATAGRAM_MAXLEN => 1024;

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
