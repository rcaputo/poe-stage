#!/usr/bin/perl
# $Id$

# Illustrate the pattern of many responses for one request.

use warnings;
use strict;

use Stage::Echoer;
use base qw(Stage);

sub init {
	my ($self, $call) = @_;

	$self->{_echoer} = Stage::Echoer->new();
	$self->{_i} = 0;

	my $c = $self->{_echoer}->echo(
		request => "message " . ++$self->{_i}
	);

	$c->on(
		type    => "echo",
		method  => "got_echo",
	);
}

sub got_echo {
	my ($self, $call) = @_;

	print "got echo: $call->{echo}\n";

	my $c = $self->{_echoer}->echo(
		request => "message " . ++$self->{_i}
	);

	$c->on(
		type    => "echo",
		method  => "got_echo",
	);
}

my $app = main->new();
$app->run();
exit;
