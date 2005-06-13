#!/usr/bin/perl
# $Id$

# This is a second version of the UDP peer code.  I've abstracted the
# original example into POE::Stage::Receiver.

use warnings;
use strict;

{
	# The application is itself a POE::Stage;

	package App;

	use warnings;
	use strict;

	use base qw(POE::Stage);
	use POE::Stage::Receiver;

	sub run {
		my ($self, $args) = @_;

		# TODO - The next two statements seem unnecessarily cumbersome.
		# What can be done to simplify them?

		$self->{req_receiver} = POE::Stage::Receiver->new();
		$self->{req_receiver_run} = POE::Request->new(
			_stage         => $self->{req_receiver},
			_method        => "listen",
			bind_port      => $args->{bind_port},
			_on_datagram   => "handle_datagram",
			_on_recv_error => "handle_error",
			_on_send_error => "handle_error",
		);
	}

	sub handle_datagram {
		my ($self, $args) = @_;

		my $datagram = $args->{datagram};
		$datagram =~ tr[a-zA-Z][n-za-mN-ZA-M];

		$self->{rsp}->recall(
			_method        => "send",
			remote_address => $args->{remote_address},
			datagram       => $datagram,
		);
	}
}

# TODO - Perhaps a magical App->run() could encapsulate the standard
# instantiation, initial requesting, and loop execution that goes on
# here.

my $bind_port = 8675;

my $app = App->new();
my $req = POE::Request->new(
	_stage    => $app,
	_method   => "run",
	bind_port => $bind_port,
);

print "You need a udp client like netcat: nc -u localhost $bind_port\n";

POE::Kernel->run();
exit;
