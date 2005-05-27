#!/usr/bin/perl
# $Id$

# Illustrate the pattern of many responses for one request.

use warnings;
use strict;

use Stage::Ticker;

# The main program is also a Stage.

use base qw(Stage);
use Carp qw(croak);

sub init {
	my ($self, $call) = @_;

	# This assumes most programming is done through "has a" means.  The
	# main program has a ticker and uses it.  I haven't explored "is a"
	# inheritance yet.

	# TODO - $self is essentially a POE::Session object here.  So
	# treating its listy object as hashy is bad.
	$self->{_ticker} = Stage::Ticker->new();

	# Tell the ticker to start ticking.  Since start_ticking() is an
	# asynchronous method, we get back a Call object instead of any sort
	# of return value.

	# TODO
	# This call generates the following error:
	# Can't use string ("interval") as a HASH ref while "strict refs" in
	# use at Ticker.pm line 68.
	#
	# Because the think doesn't exist.  The method is being called by
	# normal means.

	$self->{_name} = $call->{name};

	my $c = $self->{_ticker}->start_ticking(
		interval => $call->{interval},
	);

	# Have the current session watch for a result on the Call.  This
	# example can be read as "On a return type of 'tick', send the
	# 'got_tick' event to the current session."

	# It would be nice if the call and the watching could be done in the
	# same request.

	$c->on(
		type   => "tick",
		method => "got_tick",
	);
}

sub got_tick {
	my ($self, $call) = @_;
	print "$self->{_name} - tick: ", $call->{id}, "\n";
}

my $app_1 = main->new(
	name => "app one",
	interval => 1,
);
my $app_2 = main->new(
	name => "app two",
	interval => 1,
);

$app_1->run();
exit;
