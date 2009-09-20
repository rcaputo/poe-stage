#!/usr/bin/env perl

# Watch another object, already created.
#
# Create a Reflex::Object that may emit events before it can be
# watched.  Create a watcher after the fact, which then watches the
# Reflex::Timer.
#
# Warning: Events can be missed in a truly concurrent system if there
# is time between the creation of a watched object and registering its
# events' watchers.  See eg-02-watched-new.pl for a safer alternative.
#
# TODO - Another option is to create an object in a stopped state,
# then start it after watchers have been registered.
#
# Note: This is verbose syntax.  More concise, convenient syntax has
# been developed and appears in later examples.

use warnings;
use strict;
use lib qw(lib);

use Reflex::Object;
use Reflex::Timer;
use ExampleHelpers qw(tell);

tell("starting timer object");
my $timer = Reflex::Timer->new( interval => 1, auto_repeat => 1 );

tell("starting watcher object");
my $watcher = Reflex::Object->new();

tell("watcher watching timer");
$watcher->observe(
	observed  => $timer,
	event     => "tick",
	callback  => sub {
		tell("watcher sees 'tick' event");
	},
);

# Run the objects until they are done.
Reflex::Object->run_all();
exit;
