# $Id$

# Tied interface to a POE::Request's context.  Used to provide an
# unrestricted, hash-like interface to the request's scope without
# clashing with the request object's internal data.

package POE::Request::TiedAttributes;

use warnings;
use strict;

use Carp qw(croak);

use POE::Request qw(REQ_ID);

sub TIEHASH {
	my ($class, $self) = @_;
	return bless $self, $class;
}

sub STORE {
	my ($self, $key, $value) = @_;
	my $stage = POE::Request->_get_current_stage();
	croak "store to request context requires an active stage" unless $stage;
	return tied(%$stage)->_request_context_store($self->[REQ_ID], $key, $value);
}

sub FETCH {
	my ($self, $key) = @_;
	my $stage = POE::Request->_get_current_stage();
	croak "fetch from request context requires an active stage" unless $stage;
	return tied(%$stage)->_request_context_fetch($self->[REQ_ID], $key);
}

sub FIRSTKEY {
	my $self = shift;
	my $stage = POE::Request->_get_current_stage();
	croak "firstkey in request context requires an active stage" unless $stage;
	return tied(%$stage)->_request_context_firstkey($self->[REQ_ID]);
}

sub NEXTKEY {
	my $self = shift;
	my $stage = POE::Request->_get_current_stage();
	croak "nextkey in request context requires an active stage" unless $stage;
	return tied(%$stage)->_request_context_nextkey($self->[REQ_ID]);
}

sub EXISTS {
	my ($self, $key) = @_;
	my $stage = POE::Request->_get_current_stage();
	croak "exists in request context requires an active stage" unless $stage;
	return tied(%$stage)->_request_context_exists($self->[REQ_ID], $key);
}

sub DELETE {
	my ($self, $key) = @_;
	my $stage = POE::Request->_get_current_stage();
	croak "delete from request context requires an active stage" unless $stage;
	return tied(%$stage)->_request_context_delete($self->[REQ_ID], $key);
}

1;
