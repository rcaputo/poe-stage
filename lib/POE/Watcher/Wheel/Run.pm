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

__PACKAGE__->wheel_param_event_number( {
	StdinEvent  => 0,
	StdoutEvent => 1,
	StderrEvent => 2,
	ErrorEvent  => 3,
	CloseEvent  => 4,
} );

# Map events (by number) to parameter names for the callback method's
# $args parameter.

__PACKAGE__->wheel_event_param_names( [
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
] );

# What wheel class are we wrapping?

sub get_wheel_class {
	return "POE::Wheel::Run";
}

1;
