# $Id$

# Internally used response class that is used for $request->return().
# It subclasses POE::Request, preventing some methods from being
# called and completing instantiation in a unique way.

package POE::Request::Return;

use warnings;
use strict;
use base qw(POE::Request);
use Carp qw(croak);
use Scalar::Util qw(weaken);

use constant DEBUG => 0;

sub new {
	my ($class, %args) = @_;

	my $self = $class->_base_constructor(\%args);

	# My current request is either a Request or a Recalled
	my $current_request = POE::Request->_get_current_request();
	if ($current_request) {
		$self->{_create_stage} = $current_request->{_target_stage};
		weaken $self->{_create_stage};

		$self->{_delivery_req} = $current_request->{_parent_request};
	}
	else {
		$self->{_delivery_req} = 0;
	}

	# No need to chain back.
	$self->{_parent_request} = 0;

	$self->{_type}    = delete $args{_type};

	# Context is the delivery _req's context.
	if ($self->{_delivery_req}) {
		$self->{_context} = $self->{_delivery_req}{_context};
	}
	else {
		$self->{_context} = { };
	}

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

# Deliver the request to its destination.  Returning up out of a
# stage, so _req is this request's parent (which should be the request
# in the target that spawned the request we're returning from).  _rsp
# is zero since you can't recall down a return.

sub deliver {
	my ($self, $method) = @_;

	$self->_push($self->{_delivery_req});

	$self->{_target_stage}{_req} = $self->{_delivery_req};
	$self->{_target_stage}{_rsp} = 0;

	$self->_invoke($method || $self->{_target_method});

	my $old_rsp = delete $self->{_target_stage}{_rsp};
	my $old_req = delete $self->{_target_stage}{_req};

	die "bad _rsp" unless $old_rsp == 0;
	die "bad _req" unless $old_req == $self->{_delivery_req};

	$self->_pop($self->{_delivery_req});

	delete $self->{_delivery_req};  # circular reference
	delete $self->{_context};
}

# Some base methods are not valid here.

sub return {
	croak "Return message cannot itself be returned";
}

sub cancel {
	croak "Return message cannot be canceled";
}

sub emit {
	croak "Cannot emit a response to a return message";
}

sub recall {
	croak "Cannot recall a return message";
}

1;
