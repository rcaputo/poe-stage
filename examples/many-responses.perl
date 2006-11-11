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
	use POE::Stage qw(:base self);

	sub init :Handler {
		my $self_name = my $arg_name;
	}

	sub run :Handler {
		my ($arg_name, $arg_interval);

		my $req_ticker = POE::Stage::Ticker->new();
		my $req_name = $arg_name || "unnamed";
		my $req_interval = $arg_interval || 0.001;

		my $req_ticker_request = POE::Request->new(
			stage       => $req_ticker,
			method      => "start_ticking",
			on_tick     => "handle_tick",
			args        => {
				interval  => $req_interval,
			},
		);
	}

	sub handle_tick :Handler {
		my $arg_id;
		my $req_name;
		my $self_name;

		print(
			"app($self_name) ",
			"request($req_name) ",
			"handled tick $arg_id\n"
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
