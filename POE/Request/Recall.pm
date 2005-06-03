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

	my $self = $class->_base_constructor(\%args);

	my $current_request = POE::Request->_get_current_request();
	confess "should always have a current request" unless $current_request;

	my $current_rsp = $current_request->{_target_stage}{_rsp};
	confess "should always have a current rsp" unless $current_rsp;

	$self->{_parent_request} = $current_rsp->{_delivery_req};
	confess "rsp should always have a delivery request" unless (
		$self->{_parent_request}
	);

	$self->{_delivery_req} = $current_rsp->{_parent_request};
	confess "rsp should always have a parent request" unless (
		$self->{_delivery_req}
	);

	$self->{_create_stage} = $current_request->{_target_stage};
	weaken $self->{_create_stage};

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

# Deliver the request to its destination.
# TODO - Does this need to be different from the base?
sub deliver {
	my $self = shift;

	$self->_push($self);

	$self->{_target_stage}{_req} = $self;
	$self->{_target_stage}{_rsp} = 0;

	$self->_invoke($self->{_target_method});

	my $old_rsp = delete $self->{_target_stage}{_rsp};
	my $old_req = delete $self->{_target_stage}{_req};

	die "bad _rsp" unless $old_rsp == 0;
	die "bad _req" unless $old_req == $self;

	$self->_pop($self);
}

sub recall {
	croak "Cannot recall a recalled message";
}

1;
