# $Id$

=head1 NAME

POE::Stage::TiedAttributes - implements magic "req" and "rsp" members

=head1 SYNOPSIS

	This module is not meant to be used directly.

=head1 DESCRIPTION

POE::Stage::TiedAttributes implements a large chunk of POE::Stage's
magical data scopes.

It holds request-scoped data, which is really stage-scoped data
associated with the request.

It performs necessary cleanup when stages are destroyed or requests
are canceled.

It does these things as automatically as possible.

=head2 POE::Stage's "req" Data Member

TODO - Does not exist.  Was replaced by POE::Stage's req() export.
Move this wonderful description there.

Every POE::Stage object has two read-only data members: req and rsp.
The req data member refers to the POE::Request object that the stage
is currently handling.  Consider this request:

	my $req = POE::Request->new(
		stage  => $stage_1,
		method => "handle_it",
	);

It will be handled $stage_1's handle_it() method.  For the sake of
example, handle_it() only prints the request object:

	sub handle_it {
		my ($self, $args) = @_;
		print "$self->{req}\n";
	}

Actually, it may not be exactly the same as $req, but it will be its
moral equivalent.  This caveat leaves a loophole through which we can
later pass requests across process boundaries.

$self->{req} is also great for responding to requests:

	$self->{req}->emit( ... );
	$self->{req}->return( ... );

You should see POE::Request for more information about emit() and
return().

It should be noted that $self->{req} is valid when responses to our
own requests are being handled.  This hander cascades a return() from
a sub-request to a parent request.  It is called in response to some
request we have made, and in turn it passes a response parameter back
up the request chain.

	sub handle_a_response {
		my ($self, $args) = @_;
		my $cookie :Req;  # initialized elsewhere
		$self->{req}->return(
			type      => "done",
			args      => {
				result  => $args->{sub_result},
				cookie  => $cookie,
			},
		);
	}

=head2 POE::Stage's "rsp" Data Member

TODO - Does not exist.  Was replaced by POE::Stage's rsp() export.
Move this wonderful description there.

The special $self->{rsp} data member refers to responses to requests
made by a stage.  It's only valid when a response handler is currently
executing.  Here a response object is used to re-call a sub-stage in
response to an emitted interim response.

	sub handle_sub_response {
		my ($self, $args) = @_;
		$self->{rsp}->recall( ... );
	}

Responses share a continuation with the requests that triggered them.
Variables declared with the C<:Rsp> attribute in a response handler
refer to ones associated to the request via C<:Req($request)>.  In
other words, you can store data in the original request and have
access to it again from each corresponding response handler.

=cut

package POE::Stage::TiedAttributes;

use warnings;
use strict;

use Carp qw(croak);

sub SELF_DATA     () { 0 }  # Out-of-band data for POE::Stage.
sub STAGE_DATA    () { 1 }  # The stage's object-scoped data.
sub COMBINED_KEYS () { 2 }  # Temporary space for iteration.
sub REQUEST       () { 3 }  # Currently active request.
sub RESPONSE      () { 4 }  # Currently active response.
sub REQ_CONTEXTS  () { 5 }  # Contexts for each request in play.

use Exporter;
use base qw(Exporter);
@POE::Stage::TiedAttributes::EXPORT_OK = qw(
	REQUEST
	RESPONSE
);

sub TIEHASH {
	my $class = shift;
	my $self = bless [
		{ },    # SELF_DATA
		{ },    # STAGE_DATA
		[ ],    # COMBINED_KEYS
		undef,  # REQUEST
		undef,  # RESPONSE
		{ },    # REQ_CONTEXTS
	], $class;
	return $self;
}

sub _get_request { return $_[0][REQUEST] }
sub _get_response { return $_[0][RESPONSE] }

# We don't support direct self access anymore.  All access goes
# through :Self attributes instead.

sub STORE     { croak "storing directly to a stage";    }
sub FETCH     { croak "fetching directly from a stage"; }
sub FIRSTKEY  { croak "firstkey directly from a stage"; }
sub NEXTKEY   { croak "nextkey directly from a stage";  }
sub EXISTS    { croak "exists directly from a stage";   }
sub DELETE    { croak "delete directly from a stage";   }

### Helper for :Self members.

sub _self_store {
	my ($self, $key, $value) = @_;
	return $self->[STAGE_DATA]{$key} = $value;
}

sub _self_fetch {
	my ($self, $key) = @_;
	return $self->[STAGE_DATA]{$key};
}

sub _self_exists {
	my ($self, $key) = @_;
	return exists $self->[STAGE_DATA]{$key};
}

### Helpers for :Req members.

sub _request_context_store {
	my ($self, $req_id, $key, $value) = @_;
	return $self->[REQ_CONTEXTS]{$req_id}{$key} = $value;
}

sub _request_context_fetch {
	my ($self, $req_id, $key) = @_;
	return $self->[REQ_CONTEXTS]{$req_id}{$key};
}

sub _request_context_firstkey {
	my ($self, $req_id) = @_;
	my $a = keys %{$self->[REQ_CONTEXTS]{$req_id}};
	return each %{$self->[REQ_CONTEXTS]{$req_id}};
}

sub _request_context_nextkey {
	my ($self, $req_id) = @_;
	return each %{$self->[REQ_CONTEXTS]{$req_id}};
}

sub _request_context_exists {
	my ($self, $req_id, $key) = @_;
	return exists $self->[REQ_CONTEXTS]{$req_id}{$key};
}

sub _request_context_delete {
	my ($self, $req_id, $key) = @_;
	return delete $self->[REQ_CONTEXTS]{$req_id}{$key};
}

sub _request_context_destroy {
	my ($self, $req_id) = @_;
	delete $self->[REQ_CONTEXTS]{$req_id};
}

1;

=head1 PUBLIC METHODS

None.  This class is used implicitly when POE::Session accesses its
data members.  It is indirectly used by POE::Request as well.

=head1 BUGS

See L<http://thirdlobe.com/projects/poe-stage/report/1> for known
issues.  See L<http://thirdlobe.com/projects/poe-stage/newticket> to
report one.

=head1 SEE ALSO

L<POE::Stage> and L<POE::Request>.

=head1 AUTHORS

Rocco Caputo <rcaputo@cpan.org>.

=head1 LICENSE

POE::Stage::TiedAttributes is Copyright 2005-2006 by Rocco Caputo.
All rights are reserved.  You may use, modify, and/or distribute this
module under the same terms as Perl itself.

=cut
