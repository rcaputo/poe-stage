# $Id$

=head1 NAME

POE::Request::Upward - a base class for POE::Stage response messages

=head1 SYNOPSIS

	This module isn't meant to be used directly.

=head1 DESCRIPTION

POE::Request::Emit and POE::Request::Return share quite a lot of code.
That shared code is in this common base class.

=cut

package POE::Request::Upward;

use warnings;
use strict;

use POE::Request qw(
	REQ_CREATE_STAGE
	REQ_DELIVERY_REQ
	REQ_DELIVERY_RSP
	REQ_ID
	REQ_PARENT_REQUEST
	REQ_TARGET_METHOD
	REQ_TARGET_STAGE
	REQ_TYPE
	@EXPORT_OK
);

use base qw(POE::Request);
use Carp qw(croak confess);
use Scalar::Util qw(weaken);
use POE::Stage::TiedAttributes qw(REQUEST RESPONSE);

use constant DEBUG => 0;

=head2 new PAIRS

Create a new POE::Request response message, using PAIRS of parameters
to initialize the response.  POE::Request::Upward has one mandatory
parameter: _type.  This defines the type of response being created.
Parameters without leading underscores are the responses' payloads.
They are passed unchanged to the response's handler as its $args
parameter.

Response types are mapped to methods in the original requester's stage
through the _on_type parameters to POE::Request.  This example maps
responses of _type "success" to the requester's continue_on() method.
Likewise "error" responses are mapped to the requester's
log_and_stop() method.

	$self->{req}{foo} = POE::Request->new(
		_stage      => $some_stage_object,
		_method     => "some_method_name",
		_on_success => "continue_on",
		_on_error   => "log_and_stop",
	);

How an asynchronous TCP connector might return success and failure:

	$self->{req}->return(
		_type  => "success",
		socket => $socket,
	);

	$self->{req}->return(
		_type     => "failure",
		function  => "connect",
		errno     => $!+0,
		errstr    => "$!",
	);

=cut

sub new {
	my ($class, %args) = @_;

	# Instantiate the base request.
	my $self = $class->_request_constructor(\%args);

	# Upward requests are in response to downward ones.  Therefore a
	# current request must exist.
	my $current_request = POE::Request->_get_current_request();
	confess "should always have a current request" unless $current_request;

	# Record the stage that created this request.
	my $self_data = tied(%$self);
	my $current_data = tied(%$current_request);
	$self_data->[REQ_CREATE_STAGE] = $current_data->[REQ_TARGET_STAGE];
	weaken $self_data->[REQ_CREATE_STAGE];

	# Upward requests target the current request's parent request.
	$self_data->[REQ_DELIVERY_REQ] = $current_data->[REQ_PARENT_REQUEST];

	# Upward requests' "rsp" values point to the current request at the
	# time the upward one is created.
	$self_data->[REQ_DELIVERY_RSP] = $self;

	# The main difference between upward requests is their parents.
	$self->_init_subclass($current_request);

	# Context is the delivery req's context.  It may not always exist,
	# as in the case of an upward request leaving the top-level
	# "application" stage and returning to the outside.
	if ($self_data->[REQ_DELIVERY_REQ]) {
		my $delivery_data = tied(%{$self_data->[REQ_DELIVERY_REQ]});
#		$self_data->[REQ_CONTEXT] = $current_data->[REQ_CONTEXT];
	}
#	else {
#		$self_data->[REQ_CONTEXT] = { };
#	}

	$self_data->[REQ_ID] = $self->_reallocate_request_id(
		tied(%$current_request)->[REQ_ID]
	);

	# Upward requests can be of various types.
	$self_data->[REQ_TYPE] = delete $args{_type};

	DEBUG and warn(
		"$current_request created ", ref($self), " $self:\n",
		"\tMy parent request = $self_data->[REQ_PARENT_REQUEST]\n",
		"\tDelivery request  = $self_data->[REQ_DELIVERY_REQ]\n",
		"\tDelivery response = $self_data->[REQ_DELIVERY_RSP]\n",
	);

	$self->_assimilate_args(%args);
	$self->_send_to_target();

	return $self;
}

# Deliver the request to its destination.  This happens when the event
# carrying the request is dispatched.

sub deliver {
	my $self = shift;

	my $self_data = tied(%$self);

	my $target_stage_data = tied(%{$self_data->[REQ_TARGET_STAGE]});
	$target_stage_data->[REQUEST]  = $self_data->[REQ_DELIVERY_REQ];
	$target_stage_data->[RESPONSE] = $self_data->[REQ_DELIVERY_RSP];

	$self->_push(
		$self_data->[REQ_DELIVERY_REQ],
		$self_data->[REQ_TARGET_STAGE],
		$self_data->[REQ_TARGET_METHOD],
	);

	$self->_invoke($self_data->[REQ_TARGET_METHOD]);

	$self->_pop(
		$self_data->[REQ_DELIVERY_REQ],
		$self_data->[REQ_TARGET_STAGE],
		$self_data->[REQ_TARGET_METHOD],
	);

	my $old_rsp = splice( @$target_stage_data, RESPONSE, 1, 0 );
	my $old_req = splice( @$target_stage_data, REQUEST,  1, 0 );

#	die "bad rsp" unless $old_rsp == $self_data->[REQ_DELIVERY_RSP];
#	die "bad req" unless $old_req == $self_data->[REQ_DELIVERY_REQ];


	# Break circular references.
	$self_data->[REQ_DELIVERY_RSP] = undef;
	$self_data->[REQ_DELIVERY_REQ] = undef;
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

=head1 SEE ALSO

POE::Request::Upward has two subclasses: POE::Request::Emit for
emitting multiple responses to a single request, and
POE::Request::Return for sending a final response to end a request.

=head1 AUTHORS

Rocco Caputo <rcaputo@cpan.org>.

=head1 LICENSE

POE::Request::Upward is Copyright 2005 by Rocco Caputo.  All rights
are reserved.  You may use, modify, and/or distribute this module
under the same terms as Perl itself.

=cut
