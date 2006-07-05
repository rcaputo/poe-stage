# $Id$

# Magic to forward :Req hash access to the appropriate Request
# context within the current POE::Stage object.

package POE::Attribute::Request::Hash;

use warnings;
use strict;

use Scalar::Util qw(weaken);
use Carp qw(croak);

use constant ATT_STAGE    => 0;
use constant ATT_REQ_ID   => 1;
use constant ATT_FIELD    => 2;

sub TIEHASH {
	my ($class, $stage, $req_id, $field) = @_;

	my $self = bless [
		$stage,   # ATT_STAGE
		$req_id,  # ATT_REQ_ID
		$field,   # ATT_FIELD
	], $class;

	weaken $self->[ATT_STAGE];

	# Ensure an arrayref exists in this context slot.
	unless(tied(%$stage)->_request_context_fetch($req_id, $field)) {
		tied(%$stage)->_request_context_store($req_id, $field, { });
	}

	return $self;
}

sub FETCH {
	my ($self, $key) = @_;
	my $ref = tied(%{$self->[ATT_STAGE]})->_request_context_fetch(
		$self->[ATT_REQ_ID], $self->[ATT_FIELD]
	);
	return $ref->{$key};
}

sub STORE {
	my ($self, $key, $value) = @_;
	my $ref = tied(%{$self->[ATT_STAGE]})->_request_context_fetch(
		$self->[ATT_REQ_ID], $self->[ATT_FIELD]
	);
	return $ref->{$key} = $value;
}

sub DELETE {
	my ($self, $key) = @_;
	my $ref = tied(%{$self->[ATT_STAGE]})->_request_context_fetch(
		$self->[ATT_REQ_ID], $self->[ATT_FIELD]
	);
	return delete $ref->{$key};
}

sub CLEAR {
	my ($self) = @_;
	my $ref = tied(%{$self->[ATT_STAGE]})->_request_context_fetch(
		$self->[ATT_REQ_ID], $self->[ATT_FIELD]
	);
	return %$ref = ();
}

sub EXISTS {
	my ($self, $key) = @_;
	my $ref = tied(%{$self->[ATT_STAGE]})->_request_context_fetch(
		$self->[ATT_REQ_ID], $self->[ATT_FIELD]
	);
	return exists $ref->{$key};
}

sub FIRSTKEY {
	my ($self) = @_;
	my $ref = tied(%{$self->[ATT_STAGE]})->_request_context_fetch(
		$self->[ATT_REQ_ID], $self->[ATT_FIELD]
	);
	my $a = keys %$ref; # reset each() iterator
	return each %$ref;
}

sub NEXTKEY {
	my ($self, $lastkey) = @_;
	my $ref = tied(%{$self->[ATT_STAGE]})->_request_context_fetch(
		$self->[ATT_REQ_ID], $self->[ATT_FIELD]
	);
	return each %$ref;
}

sub SCALAR {
	my ($self) = @_;
	my $ref = tied(%{$self->[ATT_STAGE]})->_request_context_fetch(
		$self->[ATT_REQ_ID], $self->[ATT_FIELD]
	);
	return scalar %$ref;
}

1;

