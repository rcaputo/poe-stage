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

	use POE::Stage qw(rsp);
	use base qw(POE::Stage);
	use POE::Stage::Receiver;

	sub run {
		my $bind_port :Arg;

		# TODO - The next two statements seem unnecessarily cumbersome.
		# What can be done to simplify them?

		my $receiver :Req = POE::Stage::Receiver->new();
		my $receiver_run :Req = POE::Request->new(
			stage         => $receiver,
			method        => "listen",
			on_datagram   => "handle_datagram",
			on_recv_error => "handle_error",
			on_send_error => "handle_error",
			args          => {
				bind_port   => $bind_port,
			},
		);

		my $name :Req($receiver_run) = "testname";
	}

	sub handle_datagram {
		my ($datagram, $remote_address) :Arg;

		my $name :Rsp;
		print "$name received datagram: $datagram\n";
		$datagram =~ tr[a-zA-Z][n-za-mN-ZA-M];

		rsp->recall(
			method            => "send",
			args              => {
				remote_address  => $remote_address,
				datagram        => $datagram,
			},
		);
	}
}

# TODO - Perhaps a magical App->run() could encapsulate the standard
# instantiation, initial requesting, and loop execution that goes on
# here.

my $bind_port = 8675;

my $app = App->new();
my $req = POE::Request->new(
	stage       => $app,
	method      => "run",
	args        => {
		bind_port => $bind_port,
	},
);

print "You need a udp client like netcat: nc -u localhost $bind_port\n";

POE::Kernel->run();
exit;
