# $Id$

# This is a base class for requests that flow upward, from a child
# request to its parent.  Emit and Return, for example.

package POE::Request::Upward;

use warnings;
use strict;
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
	$self->{_create_stage} = $current_request->{_target_stage};
	weaken $self->{_create_stage};

	# Upward requests target the current request's parent request.
	$self->{_delivery_req} = $current_request->{_parent_request};

	# The main difference between upward requests is their parents.
	$self->_init_subclass($current_request);

	# Context is the delivery _req's context.  It may not always exist,
	# as in the case of an upward request leaving the top-level
	# "application" stage and returning to the outside.
	if ($self->{_delivery_req}) {
		$self->{_context} = $self->{_delivery_req}{_context};
	}
	else {
		$self->{_context} = { };
	}

	# Upward requests can be of various types.
	$self->{_type} = delete $args{_type};

	DEBUG and warn(
		"$current_request created $self:\n",
		"\tMy parent request = $self->{_parent_request}\n",
		"\tDelivery request  = $self->{_delivery_req}\n",
		"\tDelivery response = 0\n",
		"\tDelivery context  = $self->{_context}\n",
	);

	$self->_assimilate_args(%args);
	$self->_send_to_target();

	return $self;
}

# Deliver the request to its destination.  This happens when the event
# carrying the request is dispatched.

sub deliver {
	my $self = shift;

	$self->_push($self->{_delivery_req});

	$self->{_target_stage}{_req} = $self->{_delivery_req};
	$self->{_target_stage}{_rsp} = $self->{_delivery_rsp};

	$self->_invoke($self->{_target_method});

	my $old_rsp = delete $self->{_target_stage}{_rsp};
	my $old_req = delete $self->{_target_stage}{_req};

	die "bad _rsp" unless $old_rsp == $self->{_delivery_rsp};
	die "bad _req" unless $old_req == $self->{_delivery_req};

	$self->_pop($self->{_delivery_req});

	# Break circular references.
	delete $self->{_delivery_rsp};
	delete $self->{_delivery_req};
	delete $self->{_context};
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
