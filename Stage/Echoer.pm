# $Id$

# A sample Stage that echoes back whatever it's given.  This is used
# in ping-pong.perl to test "recursive" calls between two components.
# In reality, the calls are passed back and forth as asynchronous
# messages, so there should be no real recursion.

# Ticker.pm has more comments about what it's like to be a Stage
# object.  Look there for explanations.

package Stage::Echoer;

use warnings;
use strict;

use base qw(Stage);

sub init {
	my ($self, $call) = @_;
	# Not that we do anything...
}

sub echo :async {
	my ($self, $call) = @_;
	$call->return(
		type => "echo",
		echo => $call->{request},
	);
}

1;
