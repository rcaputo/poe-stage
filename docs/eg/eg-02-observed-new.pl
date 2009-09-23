#!/usr/bin/env perl

# An object's observers are registered during construction.
#
# By registering observers during an object's construction, there is
# no time between construction and observation where events may be
# lost.  This is equivalent to eg-01-discrete-observer.pl but without
# the potential for races.
#
# Note: This is verbose syntax.  More concise, convenient syntax has
# been developed and appears in later examples.

use warnings;
use strict;
use lib qw(../lib);

use Reflex::Object;
use Reflex::Timer;
use ExampleHelpers qw(tell);

tell("starting watcher object");
my $watcher = Reflex::Object->new( );

tell("starting timer object with integrated observation");
my $timer = Reflex::Timer->new(
	interval    => 1,
	auto_repeat => 1,
	observers   => [
		{
			observer  => $watcher,
			event     => "tick",
			callback  => sub {
				tell("watcher sees 'tick' event");
			},
		},
	],
);

# Run the objects until they are done.
Reflex::Object->run_all();
exit;
