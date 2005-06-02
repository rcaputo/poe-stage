# $Id$

# Internally used response class that is used for $request->return().
# It subclasses POE::Request, preventing some methods from being
# called and completing instantiation in a unique way.

package POE::Request::Response;

use warnings;
use strict;
use base qw(POE::Request);
use Carp qw(croak);

sub new {
	my ($class, %args) = @_;

	my $self = $class->_base_constructor(\%args);

	$self->{_type}    = delete $args{_type};
	$self->{_context} = delete $args{_context} || die;

	$self->_assimilate_args(%args);
	$self->_send_to_target();

	return $self;
}

# Deliver the request to its destination.
# TODO - Does this need to be different from the base?
sub deliver {
	my $self = shift;
	$self->_push();
	$self->_invoke($self->{_target_method});
	$self->_pop();
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

1;
