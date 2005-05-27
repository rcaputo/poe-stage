#!/usr/bin/perl
# $Id$

# Illustrate the pattern of many responses for one request.

use warnings;
use strict;

use POE;
use Call;
use Stage;

{
	package EchoServer;

	use warnings;
	use strict;

	use POE;
	use Call;

	Stage->create(
		inline_states => {
			_start  => \&start,
			echo    => \&got_request,
		},
	);

	sub start {
		$_[KERNEL]->alias_set("echoer");
	}

	sub got_request {
		my $c = $_[ARG0];
		$c->return(
			type => "echo",
			echo => $c->arg("request"),
		);
	}
}

my $i = 0;
sub send_message {
	my $c = Call->new(
		session  => "echoer",
		event    => "echo",
		request  => "hello " . ++$i,
	);

	# Have the current session watch for a result on the Call.

	$c->on(
		type     => "echo",
		event    => "got_echo",
	);

	# Send the Call on its way.

	$c->call();
}

Stage->create(
	inline_states => {
		_start => sub {
			send_message();
		},
		got_echo => sub {
			my $call = $_[ARG0];
			print $call->arg("echo"), "\n";
			send_message();
		},
	},
);

POE::Kernel->run();
exit;
