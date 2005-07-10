# $Id$

# Internally used response class that is used for $request->recall().
# It subclasses POE::Request, preventing some methods from being
# called and completing instantiation in a unique way.

package POE::Request::Recall;

use warnings;
use strict;
use Carp qw(croak confess);
use Scalar::Util qw(weaken);

use POE::Request qw(
	REQ_CONTEXT
	REQ_CREATE_STAGE
	REQ_DELIVERY_REQ
	REQ_DELIVERY_REQ
	REQ_PARENT_REQUEST
	REQ_TARGET_STAGE
);

use base qw(POE::Request);

use constant DEBUG => 0;

sub new {
	my ($class, %args) = @_;

	my $self = $class->_request_constructor(\%args);

	# Recalling downward, there should always be a current request.
	# TODO: This may not always hold true, as when recallding from
	# "main" back into the main application stage.
	my $current_request = POE::Request->_get_current_request();
	confess "should always have a current request" unless $current_request;

	my $current_req_data = tied(%$current_request);
	my $current_rsp = $current_req_data->[REQ_TARGET_STAGE]{rsp};
	confess "should always have a current rsp" unless $current_rsp;

	my $self_data = tied(%$self);
	my $current_rsp_data = tied(%$current_rsp);
	$self_data->[REQ_PARENT_REQUEST] = $current_rsp_data->[REQ_DELIVERY_REQ];
	confess "rsp should always have a delivery request" unless (
		$self_data->[REQ_PARENT_REQUEST]
	);

	# Recall targets the current response's parent request.
	$self_data->[REQ_DELIVERY_REQ] = $current_rsp_data->[REQ_PARENT_REQUEST];
	confess "rsp should always have a parent request" unless (
		$self_data->[REQ_DELIVERY_REQ]
	);

	# Record the stage that created this request.
	$self_data->[REQ_CREATE_STAGE] = $current_req_data->[REQ_TARGET_STAGE];
	weaken $self_data->[REQ_CREATE_STAGE];

	# Context is the delivery req's context.
	my $delivery_data = tied(%{$self_data->[REQ_DELIVERY_REQ]});
	$self_data->[REQ_CONTEXT] = $delivery_data->[REQ_CONTEXT];
	confess "delivery request should always have a context" unless (
		$self_data->[REQ_CONTEXT]
	);

	DEBUG and warn(
		"$self_data->[REQ_PARENT_REQUEST] created $self:\n",
		"\tMy parent request = $self_data->[REQ_PARENT_REQUEST]\n",
		"\tDelivery request  = $self\n",
		"\tDelivery response = 0\n",
		"\tDelivery context  = $self_data->[REQ_CONTEXT]\n",
	);

	$self->_assimilate_args(%args);
	$self->_send_to_target();

	return $self;
}

sub recall {
	croak "Cannot recall a recalled message";
}

1;
