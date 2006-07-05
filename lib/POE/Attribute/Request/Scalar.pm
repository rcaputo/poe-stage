# $Id$

# Magic to forward :Req scalar access to the appropriate Request
# context within the current POE::Stage object.

package POE::Attribute::Request::Scalar;

use warnings;
use strict;

use Scalar::Util qw(weaken);
use Carp qw(croak);

use constant ATT_STAGE    => 0;
use constant ATT_REQ_ID   => 1;
use constant ATT_FIELD    => 2;

sub TIESCALAR {
	my ($class, $stage, $req_id, $field) = @_;

	my $self = bless [
		$stage,   # ATT_STAGE
		$req_id,  # ATT_REQ_ID
		$field,   # ATT_FIELD
	], $class;

	weaken $self->[ATT_STAGE];

	return $self;
}

sub FETCH {
	my $self = shift;
	return(
		tied(%{$self->[ATT_STAGE]})->_request_context_fetch(
			$self->[ATT_REQ_ID], $self->[ATT_FIELD]
		)
	);
}

sub STORE {
	my ($self, $value) = @_;
	return(
		tied(%{$self->[ATT_STAGE]})->_request_context_store(
			$self->[ATT_REQ_ID], $self->[ATT_FIELD], $value
		)
	);
}

1;
