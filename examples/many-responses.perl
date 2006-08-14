#!/usr/bin/perl
# $Id$

# Illustrate the pattern of many responses for one request.

use warnings;
use strict;

{
	# The application is itself a POE::Stage;

	package App;

	use warnings;
	use strict;

	use POE::Stage::Ticker;
	use POE::Stage qw(self);
	use base qw(POE::Stage);

	sub init {
		my $name :Arg;
		my $my_name :Self = $name;
	}

	sub run {
		my ($name, $interval) :Arg;

		my $ticker :Req   = POE::Stage::Ticker->new();
		my $req_name :Req = $name || "unnamed";
		my $req_interval :Req = $interval || 0.001;

		my $ticker_request :Req = POE::Request->new(
			stage       => $ticker,
			method      => "start_ticking",
			on_tick     => "handle_tick",
			args        => {
				interval  => $req_interval,
			},
		);
	}

	sub handle_tick {
		my $id :Arg;
		my $req_name :Req;
		my $my_name :Self;

		print(
			"app($my_name) ",
			"request($req_name) ",
			"handled tick $id\n"
		);
	}
}

# TODO - Perhaps a magical App->run() could encapsulate the standard
# instantiation, initial requesting, and loop execution that goes on
# here.
#
# Although then it doesn't let us do sick things like
# multi-instantiate the application and fire off multiple startup
# events... :]

my $app_1 = App->new( name => "app_one" );

my $req_1_1 = POE::Request->new(
	stage   => $app_1,
	method  => "run",
	args    => {
		name  => "req_one",
	},
);

my $req_1_2 = POE::Request->new(
	stage   => $app_1,
	method  => "run",
	args    => {
		name  => "req_two",
	},
);

my $app_2 = App->new( name => "app_two" );

my $req_2 = POE::Request->new(
	stage   => $app_2,
	method  => "run",
	args    => {
		name  => "req_one",
	},
);

my $req_2_2 = POE::Request->new(
	stage   => $app_2,
	method  => "run",
	args    => {
		name  => "req_two",
	},
);

POE::Kernel->run();
exit;
