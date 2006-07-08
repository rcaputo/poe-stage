# $Id$

=head1 NAME

POE::Request::Return - encapsulates final replies to POE::Request messages

=head1 SYNOPSIS

	# Note, this is not a complete program.
	# See the distribution's examples directory.

	$poe_request_object->return(
		type        => "failure",
		args        => {
			function  => "connect",
			errnum    => $!+0,
			errstr    => "$!",
		},
	);

=head1 DESCRIPTION

A POE::Request::Return object is used to send a final response to a
request.  It is internally created and sent when a stage calls
$self->{req}->return(...).  Part of return()'s purpose is to cancel
the request it replies to, invalidating any further dialog associated
with the request.

=cut

package POE::Request::Return;

use warnings;
use strict;

use POE::Request::Upward qw(
	REQ_PARENT_REQUEST
	REQ_DELIVERY_RSP
);

use base qw(POE::Request::Upward);

# Return requests are defunct.  They may not be recalled.  Even though
# the parent will never be used here, it's important not to store it
# anyway.  Otherwise circular references may occur, or deeeeep
# recursion in cases where recursion isn't necessary at all.

sub _init_subclass {
	my ($self, $current_request) = @_;
	$self->[REQ_PARENT_REQUEST] = 0;
}

1;

=head1 BUGS

See http://thirdlobe.com/projects/poe-stage/report/1 for known issues.
See http://thirdlobe.com/projects/poe-stage/newticket to report one.

=head1 SEE ALSO

POE::Request::Return is comprised almost entirely of
POE::Request::Upward's features.  You should see POE::Request::Upward
for a deeper understanding of POE::Request::Return.

=head1 AUTHORS

Rocco Caputo <rcaputo@cpan.org>.

=head1 LICENSE

POE::Request::Return is Copyright 2005 by Rocco Caputo.  All rights
are reserved.  You may use, modify, and/or distribute this module
under the same terms as Perl itself.

=cut
