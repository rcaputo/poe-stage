# $Id$

=head1 NAME

POE::Stage::Resolver - a fake non-blocking DNS resolver

=head1 SYNOPSIS

	# Note, this is not a complete program.
	# See the distribution's examples directory.

	my $resolver :Req = POE::Stage::Resolver->new(
		method      => "resolve",
		on_success  => "handle_host",
		on_error    => "handle_error",
		args        => {
			input     => "thirdlobe.com",
			type      => "A",   # A is default
			class     => "IN",  # IN is default
		},
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

		my $resolver :Req = undef;
	}

=head1 DESCRIPTION

POE::Stage::Resolver is a simple non-blocking DNS resolver.  For now
it uses Net::DNS::Resolver for the bulk of its work.  It returns
Net::DNS::Packet objects in its "success" responses.  Making heads or
tails of them will require perusal of Net::DNS's documentation.

=cut

package POE::Stage::Resolver;

use warnings;
use strict;

use POE::Stage qw(:base self req);
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
	# TODO - Need an idiom to avoid direct $_[1] manipulation.

	# Fire off a request automatically as part of creation.
	my $passthrough_args = delete($_[1]{args}) || {};

	my $init_req :Req = POE::Request->new(
		stage   => self,
		method  => "resolve",
		%{$_[1]},
		args    => { %$passthrough_args },
	);

	my $resolver :Self = Net::DNS::Resolver->new();
}

sub resolve {
	my $my_type :Self = my $type :Arg; $my_type ||= "A";
	my $my_class :Self = my $class :Arg; $my_class ||= "IN";
	my $my_input :Self = my $input :Arg;
	$my_input || croak "Resolver requires input";

	my $resolver :Self;
	my $socket :Self = $resolver->bgsend(
		$my_input,
		$my_type,
		$my_class,
	);

	my $wait_for_it :Self = POE::Watcher::Input->new(
		handle    => $socket,
		on_input  => "net_dns_ready_to_read",
	);
}

sub net_dns_ready_to_read {

	my ($socket, $resolver) :Self;
	my $packet = $resolver->bgread($socket);

	my $my_input :Self;
	unless (defined $packet) {
		req->return(
			type    => "error",
			args    => {
				input => $my_input,
				error => $resolver->errorstring(),
			}
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

	req->return(
		type      => "success",
		args      => {
			input   => $my_input,
			packet  => $packet,
		},
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

See L<http://thirdlobe.com/projects/poe-stage/report/1> for known
issues.  See L<http://thirdlobe.com/projects/poe-stage/newticket> to
report one.

=head1 SEE ALSO

L<POE::Stage> and L<POE::Request>.  The examples/log-resolver.perl
program in POE::Stage's distribution.  L<Net::DNS::Packet> for an
explanation of returned packets.  L<POE::Component::Client::DNS> for
the original inspiration and a much more complete asynchronous DNS
implementation.

=head1 AUTHORS

Rocco Caputo <rcaputo@cpan.org>.

=head1 LICENSE

POE::Stage::Resolver is Copyright 2005-2006 by Rocco Caputo.  All
rights are reserved.  You may use, modify, and/or distribute this
module under the same terms as Perl itself.

=cut
