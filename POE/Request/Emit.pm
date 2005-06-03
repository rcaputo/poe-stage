# $Id$

# Internally used response class that is used for $request->emit().
# It subclasses POE::Request, preventing some methods from being
# called and completing instantiation in a unique way.

package POE::Request::Emit;

use warnings;
use strict;
use base qw(POE::Request);
use Carp qw(croak);
use Scalar::Util qw(weaken);

use constant DEBUG => 0;

sub new {
	my ($class, %args) = @_;

	my $self = $class->_base_constructor(\%args);

	my $current_request = POE::Request->_get_current_request();
	$self->{_parent_request} = $current_request;

	if ($current_request) {
		$self->{_create_stage} = $current_request->{_target_stage};
		weaken $self->{_create_stage};

		$self->{_delivery_req} = $current_request->{_parent_request};
	}
	else {
		$self->{_delivery_req} = 0;
	}

	$self->{_type} = delete $args{_type};

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

# Deliver the request to its destination.

sub deliver {
	my $self = shift;

	$self->_push($self->{_delivery_req});

	$self->{_target_stage}{_req} = $self->{_delivery_req};
	$self->{_target_stage}{_rsp} = $self;

	$self->_invoke($self->{_target_method});

	my $old_rsp = delete $self->{_target_stage}{_rsp};
	my $old_req = delete $self->{_target_stage}{_req};

	die "bad _rsp" unless $old_rsp == $self;
	die "bad _req" unless $old_req == $self->{_delivery_req};

	$self->_pop($self->{_delivery_req});
}

# Some base methods are not valid here.

sub return {
	croak "Return message cannot itself be returned";
}

sub cancel {
	croak "Return message cannot be canceled";
}

sub recall {
	my ($self, %args) = @_;
	$self->_recall(%args);
}

1;
