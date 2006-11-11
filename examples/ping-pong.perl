#!/usr/bin/perl
# $Id$

# Illustrate the pattern of many one request per response, where each
# response triggers another request.  This often leads to infinite
# recursion and stacks blowing up, so it's important to be sure the
# system works right in this case.

use warnings;
use strict;

{
	# The application is itself a POE::Stage.

	package App;

	use warnings;
	use strict;

	use POE::Stage::Echoer;
	use POE::Stage qw(:base self);

	sub run :Handler {
		my $req_echoer = POE::Stage::Echoer->new();
		my $req_i = 1;

		self->send_request();
	}

	sub got_echo :Handler {
		my $arg_echo;

		print "got echo: $arg_echo\n";

		my $req_i;
		$req_i++;

		# Comment out this line to run indefinitely.  Great for checking
		# for memory leaks.
#		return if $i > 10;

		self->send_request();
	}

	sub send_request :Handler {
		my ($req_i, $req_echoer);
		my $req_echo_request = POE::Request->new(
			stage     => $req_echoer,
			method    => "echo",
			on_echo   => "got_echo",
			args      => {
				message => "request $req_i",
			},
		);
	}
}

# TODO - Perhaps a magical App->run() could encapsulate the standard
# instantiation, initial requesting, and loop execution that goes on
# here.

my $app = App->new();

my $req = POE::Request->new(
	stage   => $app,
	method  => "run",
);

POE::Kernel->run();
exit;
