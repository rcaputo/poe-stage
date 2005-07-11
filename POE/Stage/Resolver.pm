# $Id$

# A non-blocking DNS stage.
# TODO - It cheats.  Make it not cheat.

package POE::Stage::Resolver;

use warnings;
use strict;

use base qw(POE::Stage);
use POE::Watcher::Delay;

sub resolve_to_host {
	my ($self, $args) = @_;

	my $address = $args->{address};
	$self->{req}{$address} = POE::Watcher::Delay->new(
		_length     => rand(2),
		_on_success => "net_dns_ready_to_read",
		address     => $address,
	);
}

sub net_dns_ready_to_read {
	my ($self, $args) = @_;

	my $address = $args->{address};

	# TODO - We deliberately do NOT return the address here, although it
	# seems like the stage would be easier to use if we did.  Why?  To
	# force the user to store data in the request's scope.
	$self->{req}->return(
		_type => "host",
		host  => "host($address)",
	);
}

1;
