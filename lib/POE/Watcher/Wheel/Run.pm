# $Id$

# TODO - Documentation.

package POE::Watcher::Wheel::Run;

use warnings;
use strict;
use POE::Watcher::Wheel;
use POE::Wheel::Run;
use base qw(POE::Watcher::Wheel);

# Map wheel "event" parameters to event numbers.  POE::Stage currently
# can handle events 0..4.  It should be extended if you need more.

my %wheel_param_event_number = (
	StdinEvent  => 0,
	StdoutEvent => 1,
	StderrEvent => 2,
	ErrorEvent  => 3,
	CloseEvent  => 4,
);

# Map events (by number) to parameter names for the callback method's
# $args parameter.

my @wheel_event_param_names = (
	# 0 = StdinEvent
	[ "wheel_id" ],

	# 1 = StdoutEvent
	[ "output", "wheel_id" ],

	# 2 = StderrEvent
	[ "output", "wheel_id" ],

	# 3 = ErrorEvent
	[ "operation", "errnum", "errstr", "wheel_id", "handle_name" ],

	# 4 = CloseEvent
	[ "wheel_id" ],
);

# Ideally this should be a base class method, but then it wouldn't see
# the parameters here.  I think this is why mst suggested that
# inheritable parameters class that I can't remember now.

sub wheel_param_to_event_number {
	my ($self, $param) = @_;
	my $wheel_param_event_number = $wheel_param_event_number{$param};
	die $param unless defined $wheel_param_event_number;
	return $wheel_param_event_number;
}

# Likewise, an accessor for parameter names.

sub wheel_param_names {
	my ($class, $event_number) = @_;
	die unless $wheel_event_param_names[$event_number];
	return $wheel_event_param_names[$event_number];
}

# What wheel class are we wrapping?

sub get_wheel_class {
	return "POE::Wheel::Run";
}

1;
