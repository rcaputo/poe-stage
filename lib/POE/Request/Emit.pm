# $Id$

=head1 NAME

POE::Request::Emit - a class encapsulating non-terminal replies to POE::Request

=head1 SYNOPSIS

	# Note, this is not a complete program.
	# See the distribution's examples directory.

	$poe_request_object->emit(
		_type     => "failure",
		function  => "connect",
		errnum    => $!+0,
		errstr    => "$!",
	);

=head1 DESCRIPTION

POE::Request::Emit is a class whose objects are created transparently
when emit() is called on POE::Request objects.  These objects
represent responses to POE::Request objects, but they do not cancel
their trigger request.  This allows a stage to emit multiple events
for a single request, finally calling return() or cancel() to end the
request.

=cut

package POE::Request::Emit;

use warnings;
use strict;
use Carp qw(croak confess);

use POE::Request::Upward qw(
	REQ_DELIVERY_RSP
	REQ_PARENT_REQUEST
	REQ_CREATE_STAGE
);

use base qw(POE::Request::Upward);

# Emitted requests may be recall()ed.  Therefore they need parentage.

sub _init_subclass {
	my ($self, $current_request) = @_;
	my $self_data = tied(%$self);
	$self_data->[REQ_PARENT_REQUEST] = $current_request;
}

=head2 recall PAIRS

recall() is used to respond to emit().  It creates a new
POE::Request::Recall object, passing the specified PAIRS of arguments
to its constructor.  Once constructed, the recall message is
automatically sent to the source of the POE::Request::Emit object.

You'll need to see POE::Request::Recall for details on constructing
recall messages.

=cut

sub recall {
	my ($self, %args) = @_;

	# Where does the message go?
	# TODO - Have croak() reference the proper package/file/line.

	my $self_data = tied(%$self);
	my $parent_stage = $self_data->[REQ_CREATE_STAGE];
	unless ($parent_stage) {
		confess "Cannot recall message: The requester is not a POE::Stage class";
	}

	# Validate the method.
	my $message_method = delete $args{_method};
	croak "Message must have a _method parameter" unless defined $message_method;

	# Reconstitute the parent's context.
	my $parent_context;
	my $parent_request = $self_data->[REQ_PARENT_REQUEST];
	croak "Cannot recall message: The requester has no context" unless (
		$parent_request
	);

	my $response = POE::Request::Recall->new(
		%args,
		_stage   => $parent_stage,
		_method  => $message_method,
	);
}

1;

=head1 SEE ALSO

POE::Request, POE::Request::Recall, and probably POE::Stage.

=head1 AUTHORS

Rocco Caputo <rcaputo@cpan.org>.

=head1 LICENSE

POE::Request::Emit is Copyright 2005 by Rocco Caputo.  All rights are
reserved.  You may use, modify, and/or distribute this module under
the same terms as Perl itself.

=cut
