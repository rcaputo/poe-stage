# $Id$

=head1 NAME

POE::Stage::Resolver - a fake non-blocking DNS resolver

=head1 SYNOPSIS

	# Note, this is not a complete program.
	# See the distribution's examples directory.

	$self->{req}{resolver} = POE::Stage::Resolver->new(
		_method     => "resolve",
		_on_success => "handle_host",
		_on_error   => "handle_error",
		input       => "thirdlobe.com",
		type        => "A",   # A is default
		class       => "IN",  # IN is default
	);

	sub handle_host {
		my ($self, $args) = @_;

		my $input  = $args->{input};
		my $packet = $args->{packet};

		my @answers = $packet->answer();
		foreach my $answer (@answers) {
			print(
				"Resolved: $input = type(", $answer->type(), ") data(",
				$answer->rdatastr, ")\n"
			);
		}

		delete $self->{req}{resolver};
	}

=head1 DESCRIPTION

POE::Stage::Resolver is a simple non-blocking DNS resolver.  It uses
Net::DNS::Resolver for the bulk of its work.  It returns
Net::DNS::Packet objects in its "success" responses.  Making heads or
tails of them will require perusal of Net::DNS's documentation.

=cut

package POE::Stage::Resolver;

use warnings;
use strict;

use base qw(POE::Stage);
use POE::Watcher::Delay;
use Net::DNS::Resolver;
use POE::Watcher::Input;
use Carp qw(croak);

=head1 PUBLIC COMMANDS

Commands are invoked with POE::Request objects.

=head2 new (input => INPUT, type => TYPE, class => CLASS)

Creates a POE::Stage::Resolver instance and asks it to resolve some
INPUT into records of a given CLASS and TYPE.  CLASS and TYPE default
to "IN" and "A", respectively.

When complete, the stage will return either a "success" or an "error".

=cut

sub init {
	my ($self, $args) = @_;

	# Fire off a request automatically as part of creation.
	$self->{init_req} = POE::Request->new(
		_stage  => $self,
		_method => "resolve",
		%$args,
	);

	$self->{resolver} = Net::DNS::Resolver->new();
}

sub resolve {
	my ($self, $args) = @_;

	$self->{type}  = $args->{type} || "A";
	$self->{class} = $args->{class} || "IN";
	$self->{input} = $args->{input} || croak "Resolver requires input";

	my $resolver_socket = $self->{resolver}->bgsend(
		$self->{input},
		$self->{type},
		$self->{class},
	);

	$self->{socket} = $resolver_socket;

	$self->{wait_for_it} = POE::Watcher::Input->new(
		_handle   => $resolver_socket,
		_on_input => "net_dns_ready_to_read",
	);
}

sub net_dns_ready_to_read {
	my ($self, $args) = @_;

	my $socket = $self->{socket};
	my $packet = $self->{resolver}->bgread($socket);

	unless (defined $packet) {
		$self->{req}->return(
			_type   => "error",
			input   => $self->{input},
			error   => $self->{resolver}->errorstring(),
		);
		return;
	}

	unless (defined $packet->answerfrom) {
		my $answerfrom = getpeername($socket);
		if (defined $answerfrom) {
			$answerfrom = (unpack_sockaddr_in($answerfrom))[1];
			$answerfrom = inet_ntoa($answerfrom);
			$packet->answerfrom($answerfrom);
		}
	}

	$self->{req}->return(
		_type   => "success",
		input   => $self->{input},
		packet  => $packet,
	);

#	# Dump things when we should be done with them.  Originally used to
#	# find a memory leak in self-requesting stages.
#	use Data::Dumper;
#
#	warn "*********** self :\n";
#	warn Dumper($self), "\n";
#	warn Dumper(tied(%{$self->{init_req}}));
#
#	delete $self->{init_req};
#	delete $self->{wait_for_it};
}

1;

=head1 PUBLIC RESPONSES

Responses are returned by POE::Request->return() or emit().

=head2 "success" (input, packet)

Net::DNS::Resolver successfully resolved a request.  The original
input is passed back in the "input" parameter.  The resulting
Net::DNS::Packet object is returned in "packet".

=head2 "error" (input, error)

Net::DNS::Resolver, or something else, failed to resolve the input to
a response.  The original input is passed back in the "input"
parameter.  Net::DNS::Resolver's error message comes back as "error".

=head1 BUGS

See http://thirdlobe.com/projects/poe-stage/report/1 for known issues.
See http://thirdlobe.com/projects/poe-stage/newticket to report one.

=head1 SEE ALSO

POE::Stage and POE::Request.  The examples/log-resolver.perl program
in POE::Stage's distribution.  Net::DNS::Packet for an explanation of
returned packets.  POE::Component::Client::DNS for the original
inspiration.

=head1 AUTHORS

Rocco Caputo <rcaputo@cpan.org>.

=head1 LICENSE

POE::Stage::Resolver is Copyright 2005 by Rocco Caputo.  All rights
are reserved.  You may use, modify, and/or distribute this module
under the same terms as Perl itself.

=cut
