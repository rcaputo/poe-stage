# $Id$

=head1 NAME

POE::Stage::Resolver - a simple non-blocking DNS resolver

=head1 SYNOPSIS

	# Note, this is not a complete program.
	# See the distribution's examples directory.

	sub some_handler :Handler {
		my $req_resolver = POE::Stage::Resolver->new(
			method      => "resolve",
			on_success  => "handle_host",
			on_error    => "handle_error",
			args        => {
				input     => "thirdlobe.com",
				type      => "A",   # A is default
				class     => "IN",  # IN is default
			},
		);
	}

	sub handle_host :Handler {
		my ($arg_input, $arg_packet);

		my @answers = $arg_packet->answer();
		foreach my $answer (@answers) {
			print(
				"Resolved: $arg_input = type(", $answer->type(), ") data(",
				$answer->rdatastr, ")\n"
			);
		}

		# Cancel the resolver by destroying it.
		my $req_resolver = undef;
	}

=head1 DESCRIPTION

POE::Stage::Resolver is a simple non-blocking DNS resolver.  For now
it uses Net::DNS::Resolver for the bulk of its work.  It returns
Net::DNS::Packet objects in its "success" responses.  Making heads or
tails of them will require perusal of Net::DNS's documentation.

=cut

package POE::Stage::Resolver;

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

When complete, the stage will return either a "success" or an "error"
message.

=cut

sub init :Handler {
	# TODO - Need an idiom to avoid direct $_[1] manipulation.

	# Fire off a request automatically as part of creation.
	my $passthrough_args = delete($_[1]{args}) || {};

	my $req_init_req = POE::Request->new(
		stage   => self,
		method  => "resolve",
		%{$_[1]},
		args    => { %$passthrough_args },
	);

	my $self_resolver = Net::DNS::Resolver->new();
}

sub resolve :Handler {
	my $self_type = my $arg_type; $self_type ||= "A";
	my $self_class = my $arg_class; $self_class ||= "IN";
	my $self_input = my $arg_input;
	$self_input || croak "Resolver requires input";

	my $self_resolver;
	my $self_socket = $self_resolver->bgsend(
		$self_input,
		$self_type,
		$self_class,
	);

	my $self_wait_for_it = POE::Watcher::Input->new(
		handle    => $self_socket,
		on_input  => "net_dns_ready_to_read",
	);
}

sub net_dns_ready_to_read :Handler {

	my ($self_socket, $self_resolver);
	my $packet = $self_resolver->bgread($self_socket);

	my $self_input;
	unless (defined $packet) {
		req->return(
			type    => "error",
			args    => {
				input => $self_input,
				error => $self_resolver->errorstring(),
			}
		);
		return;
	}

	unless (defined $packet->answerfrom) {
		my $answerfrom = getpeername($self_socket);
		if (defined $answerfrom) {
			$answerfrom = (unpack_sockaddr_in($answerfrom))[1];
			$answerfrom = inet_ntoa($answerfrom);
			$packet->answerfrom($answerfrom);
		}
	}

	req->return(
		type      => "success",
		args      => {
			input   => $self_input,
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


POE::Stage is too young for production use.  For example, its syntax
is still changing.  You probably know what you don't like, or what you
need that isn't included, so consider fixing or adding that, or at
least discussing it with the people on POE's mailing list or IRC
channel.  Your feedback and contributions will bring POE::Stage closer
to usability.  We appreciate it.

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
