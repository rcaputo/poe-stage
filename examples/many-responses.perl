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
	use base qw(POE::Stage);

	sub init {
		my ($self, $args) = @_;
		$self->{name} = $args->{name};
	}

	sub run {
		my ($self, $args) = @_;

		$self->{req}{ticker}   = POE::Stage::Ticker->new();
		$self->{req}{name}     = $args->{name} || "unnamed";
		$self->{req}{interval} = $args->{interval} || 0.001;

		$self->{req}{ticker_request} = POE::Request->new(
			stage       => $self->{req}{ticker},
			method      => "start_ticking",
			on_tick     => "handle_tick",
			args        => {
				interval  => $self->{req}{interval},
			},
		);
	}

	sub handle_tick {
		my ($self, $args) = @_;
		print(
			"app($self->{name}) ",
			"request($self->{req}{name}) ",
			"handled tick $args->{id}\n"
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
