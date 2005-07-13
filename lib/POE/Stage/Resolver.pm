# $Id$

=head1 NAME

POE::Stage::Resolver - a fake non-blocking DNS resolver

=head1 SYNOPSIS

	# Note, this is not a complete program.
	# See the distribution's examples directory.

	$self->{req}{resolver} = POE::Stage::Resolver->new();
	$self->{req}{subreq} = POE::Request->new(
		_stage        => $stage,
		_method       => "resolve_to_host",
		_on_host      => "handle_host",
		_on_error     => "handle_error",
		address       => "thirdlobe.com",
	);
	$self->{req}{subreq}{host} = "thirdlobe.com";

	sub handle_host {
		my ($self, $args) = @_;
		print "$self->{rsp}{host} resolves to $args->{address}\n";
	}

=head1 DESCRIPTION

POE::Stage::Resolver is a non-function mock-up of a non-blocking DNS
resolver.  Its guts will be replaced later with fully functional ones,
and programs using it will suddenly work a whole lot better...
assuming they work even partially to begin with.

=cut

package POE::Stage::Resolver;

use warnings;
use strict;

use base qw(POE::Stage);
use POE::Watcher::Delay;

=head2 resolve_to_host address => ADDRESS

Starts as asynchronous address to host DNS lookup.
POE::Stage::Resolver eventually sends back a message of type "host" or
"error" depending on the success of the resolution.

The "host" message includes a host field containing, predictably
enough, the host that was found at a given address.

The "error" message's fields are not yet defined.  This mock-up
doesn't ever fail.

=cut

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

=head1 SEE ALSO

POE::Stage and POE::Request.  The examples/log-resolver.perl program
in POE::Stage's distribution.

=head1 AUTHORS

Rocco Caputo <rcaputo@cpan.org>.

=head1 LICENSE

POE::Stage::Resolver is Copyright 2005 by Rocco Caputo.  All rights
are reserved.  You may use, modify, and/or distribute this module
under the same terms as Perl itself.

=cut
