# $Id$

=head1 NAME

POE::Request::TiedAttributes - internal class for request-scoped storage

=head1 SYNOPSIS

	This module is not meant to be used directly.

=head1 DESCRIPTION

POE::Request::TiedAttributes is used to map hash operations on
requests into request-scoped storage within stages.  For example:

  my $request = POE::Request->new(...);
	$request->{key} = $value;

really stores $value within the current POE::Stage object in such a
way that it is visible when a response arrives.  This magic is
performed in two steps: 1. POE::Stage ensures that $self->{rsp} is the
response to a given request.  2. The response's storage scope is also
made to match its request.

The upshot is that $self->{rsp}{key} contains the value of
$request->{key} when it is invoked from a response callback.

This is how POE::Stage and POE::Request implement continuity between
asynchronous requests and their responses.

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

=head1 PUBLIC METHODS

None.  This class is used implicitly when POE::Request classes are
treated like hashes.

=head1 DESIGN GOALS

Store request-scoped data in the session that stores it, rather than
in the request itself.  The receiver of a request cannot This prevents the receiver of a request from
modifying data that the sender requires.  It also avoids serialization
problems that may occur in the future when requests are passed between
processes.

Use an intuitive and unobtrusive syntax for request-scoped data.
POE::Request and POE::Stage could have used accessors, but tied hashes
take advantage of Perl's existing syntax.

=head1 BUGS

See http://thirdlobe.com/projects/poe-stage/report/1 for known issues.
See http://thirdlobe.com/projects/poe-stage/newticket to report one.

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
