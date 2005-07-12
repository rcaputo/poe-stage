# $Id$

# Internal request class that is used for $request->emit().  It
# subclasses POE::Request::Upward, customizing certain methods and
# tweaking instantiation where necessary.

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

# Override recall() because we can do that from Emit.

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