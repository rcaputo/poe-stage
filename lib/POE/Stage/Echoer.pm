# $Id$

=head1 NAME

POE::Stage::Echoer - a stage that echoes back whatever it's given

=head1 SYNOPSIS

	# Note, this is not a complete program.
	# See the distribution's examples directory.

	use POE::Stage::Echoer;
	my $stage = POE::Stage::Echoer->new();

	my $req = POE::Request->new(
		stage     => $stage,
		method    => "echo",
		on_echo   => "handle_echo",
		args      => {
			message => "stuff to echo",
		},
	);

	sub handle_echo {
		my ($self, $args) = @_;
		print "Received an echo: $args->{echo}\n";
	}

=head1 DESCRIPTION

POE::Stage::Echoer receives messages through its echo() method.
echo() sends back the contents of its "message" parameter as the
"echo" parameter of an "echo" response message.

Ok, that's confusing.  Perhaps the SYNOPSIS is clearer?

TODO - It would be nice to have a documentation convention for this
sort of things.

=cut

package POE::Stage::Echoer;

use warnings;
use strict;

use base qw(POE::Stage);

=head1 PUBLIC COMMANDS

Commands are invoked with POE::Request objects.

=head2 echo (message => SCALAR)

Receives a scalar "message" parameter whose contents will be echoed
back to the sender.  The message is echoed with a return of type
"echo".  The return message's "echo" parameter contains the original
message.

=cut

sub echo {
	my ($self, $args) = @_;

	$self->{req}->return(
		type    => "echo",
		args    => {
			echo  => $args->{message},
		},
	);
}

1;

=head1 PUBLIC RESPONSES

Responses are returned by POE::Request->return() or emit().

=head2 "echo" (echo => SCALAR)

Returns an echo of the "message" given to this stage's echo() command.
The echo is passed in the "echo" parameter to the "echo" response.

=head1 BUGS

See http://thirdlobe.com/projects/poe-stage/report/1 for known issues.
See http://thirdlobe.com/projects/poe-stage/newticket to report one.

=head1 SEE ALSO

POE::Stage and POE::Request.  The examples/ping-poing.perl program in
POE::Stage's distribution.

=head1 AUTHORS

Rocco Caputo <rcaputo@cpan.org>.

=head1 LICENSE

POE::Stage::Echoer is Copyright 2005-2006 by Rocco Caputo.  All rights
are reserved.  You may use, modify, and/or distribute this module
under the same terms as Perl itself.

=cut
