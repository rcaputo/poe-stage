# $Id$

# Internally used response class that is used for $request->recall().
# It subclasses POE::Request, preventing some methods from being
# called and completing instantiation in a unique way.

package POE::Request::Recall;

use warnings;
use strict;
use base qw(POE::Request);
use Carp qw(croak confess);
use Scalar::Util qw(weaken);

use constant DEBUG => 0;

sub new {
	my ($class, %args) = @_;

	my $self = $class->_request_constructor(\%args);

	# Recalling downward, there should always be a current request.
	# TODO: This may not always hold true, as when recallding from
	# "main" back into the main application stage.
	my $current_request = POE::Request->_get_current_request();
	confess "should always have a current request" unless $current_request;

	my $current_rsp = $current_request->{_target_stage}{_rsp};
	confess "should always have a current rsp" unless $current_rsp;

	$self->{_parent_request} = $current_rsp->{_delivery_req};
	confess "rsp should always have a delivery request" unless (
		$self->{_parent_request}
	);

	# Recall targets the current response's parent request.
	$self->{_delivery_req} = $current_rsp->{_parent_request};
	confess "rsp should always have a parent request" unless (
		$self->{_delivery_req}
	);

	# Record the stage that created this request.
	$self->{_create_stage} = $current_request->{_target_stage};
	weaken $self->{_create_stage};

	# Context is the delivery _req's context.
	$self->{_context} = $self->{_delivery_req}{_context};
	confess "delivery request should always have a context" unless (
		$self->{_context}
	);

	DEBUG and warn(
		"$self->{_parent_request} created $self:\n",
		"\tMy parent request = $self->{_parent_request}\n",
		"\tDelivery request  = $self\n",
		"\tDelivery response = 0\n",
		"\tDelivery context  = $self->{_context}\n",
	);

	$self->_assimilate_args(%args);
	$self->_send_to_target();

	return $self;
}

sub recall {
	croak "Cannot recall a recalled message";
}

1;
