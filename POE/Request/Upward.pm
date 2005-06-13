# $Id$

# This is a base class for requests that flow upward, from a child
# request to its parent.  Emit and Return, for example.

package POE::Request::Upward;

use warnings;
use strict;

use POE::Request qw(
	REQ_CONTEXT
	REQ_CREATE_STAGE
	REQ_DELIVERY_REQ
	REQ_DELIVERY_RSP
	REQ_PARENT_REQUEST
	REQ_TARGET_METHOD
	REQ_TARGET_STAGE
	REQ_TYPE
	@EXPORT_OK
);

use base qw(POE::Request);
use Carp qw(croak confess);
use Scalar::Util qw(weaken);

use constant DEBUG => 0;

sub new {
	my ($class, %args) = @_;

	# Instantiate the base request.
	my $self = $class->_request_constructor(\%args);

	# Upward requests are in response to downward ones.  Therefore a
	# current request must exist.
	my $current_request = POE::Request->_get_current_request();
	confess "should always have a current request" unless $current_request;

	# Record the stage that created this request.
	$self->[REQ_CREATE_STAGE] = $current_request->[REQ_TARGET_STAGE];
	weaken $self->[REQ_CREATE_STAGE];

	# Upward requests target the current request's parent request.
	$self->[REQ_DELIVERY_REQ] = $current_request->[REQ_PARENT_REQUEST];

	# The main difference between upward requests is their parents.
	$self->_init_subclass($current_request);

	# Context is the delivery req's context.  It may not always exist,
	# as in the case of an upward request leaving the top-level
	# "application" stage and returning to the outside.
	if ($self->[REQ_DELIVERY_REQ]) {
		$self->[REQ_CONTEXT] = $self->[REQ_DELIVERY_REQ][REQ_CONTEXT];
	}
	else {
		$self->[REQ_CONTEXT] = { };
	}

	# Upward requests can be of various types.
	$self->[REQ_TYPE] = delete $args{_type};

	DEBUG and warn(
		"$current_request created $self:\n",
		"\tMy parent request = $self->[REQ_PARENT_REQUEST]\n",
		"\tDelivery request  = $self->[REQ_DELIVERY_REQ]\n",
		"\tDelivery response = 0\n",
		"\tDelivery context  = $self->[REQ_CONTEXT]\n",
	);

	$self->_assimilate_args(%args);
	$self->_send_to_target();

	return $self;
}

# Deliver the request to its destination.  This happens when the event
# carrying the request is dispatched.

sub deliver {
	my $self = shift;

	$self->_push($self->[REQ_DELIVERY_REQ]);

	$self->[REQ_TARGET_STAGE]{req} = $self->[REQ_DELIVERY_REQ];
	$self->[REQ_TARGET_STAGE]{rsp} = $self->[REQ_DELIVERY_RSP];

	$self->_invoke($self->[REQ_TARGET_METHOD]);

	my $old_rsp = delete $self->[REQ_TARGET_STAGE]{rsp};
	my $old_req = delete $self->[REQ_TARGET_STAGE]{req};

	die "bad rsp" unless $old_rsp == $self->[REQ_DELIVERY_RSP];
	die "bad req" unless $old_req == $self->[REQ_DELIVERY_REQ];

	$self->_pop($self->[REQ_DELIVERY_REQ]);

	# Break circular references.
	delete $self->[REQ_DELIVERY_RSP];
	delete $self->[REQ_DELIVERY_REQ];
	delete $self->[REQ_CONTEXT];
}

# Rules for all upward messages.

sub return {
	my $class = ref(shift());
	croak "cannot return from upward $class";
}

sub cancel {
	my $class = ref(shift());
	croak "cannot cancel upward $class";
}

sub emit {
	my $class = ref(shift());
	croak "cannot emit from upward $class";
}

sub recall {
	my $class = ref(shift());
	croak "cannot recall from upward $class";
}

1;
