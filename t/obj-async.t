#!/usr/bin/perl
# vim: filetype=perl

# Test asynchronous objects.
# Ensure they're called properly.
# Ensure they're destroyed properly.

use warnings;
use strict;
use Test::More qw(no_plan);

{ package Async;
	use base qw(Stage);

	sub init {
		my ($self, $call) = @_;
		$self->{name} = $call->{name};
	}

	sub name :async {
		my ($self, $call) = @_;
		$call->return(
			type => "name",
			name => $self->{name},
		);
	}

	sub DESTROY {
		my $self = shift;
		warn "destroying $self";
	}
}

{ package App;
	use base qw(Stage);

	sub init {
		my ($self, $call) = @_;
		$self->{async} = Async->new(name => "one");
		my $c = $self->{async}->name();
		$c->on(
			type    => "name",
			method  => "got_name",
		);
	}

	sub got_name {
		my ($self, $call) = @_;
		use YAML;
		warn YAML::Dump($call);
	}
}

my $app = App->new();
$app->run();
exit;
