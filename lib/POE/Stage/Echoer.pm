# $Id$

=head1 NAME

POE::Stage::Echoer - a stage that echoes back whatever it's given

=head1 SYNOPSIS

	# Note, this is not a complete program.
	# See the distribution's examples directory.

	use POE::Stage::Echoer;
	my $stage = POE::Stage::Echoer->new();

	my $req = POE::Request->new(
		_stage   => $stage,
		_method  => "echo",
		message  => "stuff to echo",
		_on_echo => "handle_echo",
	);

	sub handle_echo {
		my ($self, $args) = @_;
		print "Received an echo: $args->{echo}\n";
	}

=head1 DESCRIPTION

POE::Stage::Echoer receives messages through its echo() method.  It
echoes back the "message" parameter of echo() as the "echo" parameter
of an "echo" message.

Ok, that's confusing.  Perhaps the SYNOPSIS is clearer?

=cut

package POE::Stage::Echoer;

use warnings;
use strict;

use base qw(POE::Stage);

=head2 echo message => SCALAR

Receives a scalar "message" parameter whose contents will be echoed
back to the sender.  The message is echoed with a return of _type
"echo".  The return message's "echo" parameter contains a copy of the
original message.

=cut

sub echo {
	my ($self, $args) = @_;

	$self->{req}->return(
		_type => "echo",
		echo  => $args->{message},
	);
}

1;

=head1 SEE ALSO

POE::Stage and POE::Request.  The examples/ping-poing.perl program in
POE::Stage's distribution.

=head1 AUTHORS

Rocco Caputo <rcaputo@cpan.org>.

=head1 LICENSE

POE::Stage::Echoer is Copyright 2005 by Rocco Caputo.  All rights are
reserved.  You may use, modify, and/or distribute this module under
the same terms as Perl itself.

=cut
