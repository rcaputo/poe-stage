# $Id$

# This sample POE::Stage echoes back whatever it's given.

package POE::Stage::Echoer;

use warnings;
use strict;

use base qw(POE::Stage);

sub echo {
	my ($self, $args) = @_;

	$self->{req}->return(
		_type => "echo",
		echo  => $args->{message},
	);
}

1;
