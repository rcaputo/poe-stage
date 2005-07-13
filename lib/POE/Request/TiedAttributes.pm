# $Id$

=head1 NAME

POE::Request::TiedAttributes - implements request-scoped data storage

=head1 SYNOPSIS

	This module is not meant to be used directly.

=head1 DESCRIPTION

POE::Requset::TiedAttributes and POE::Stage::TiedAttributes are used
to map hash access in request objects to request-scoped storage in
stage objects.  Honest.  For example:

	$self->{req}{key} = $value;

treats the request in $self->{req} as a hash, storing key = $value
within it.  The implementation actually stores the key/$value pair
inside the current POE::Stage object, under the $self->{req} request's
scope.  The key/$value pair will be available as $self->{req}{key}
whenever $self->{req} refers to the same request as at storage time.

Furthermore, if $self->{req}{foo} is a POE::Request object, then
$self->{rsp}{foo} will refer to its value whenever $self->{rsp} is a
response to $self->{req}{foo}.

This is how POE::Stage and POE::Request implement continuations
between asynchronous requests and their responses.

=cut

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

=head1 SEE ALSO

POE::Stage::TiedAttributes, which implements the POE::Stage side of
this magic and discusses the special req and rsp data members in
detail.

=head1 AUTHORS

Rocco Caputo <rcaputo@cpan.org>.

=head1 LICENSE

POE::Request::TiedAttributes is Copyright 2005 by Rocco Caputo.  All
rights are reserved.  You may use, modify, and/or distribute this
module under the same terms as Perl itself.

=cut
