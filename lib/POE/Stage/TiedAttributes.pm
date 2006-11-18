# $Id$

=head1 NAME

POE::Stage::TiedAttributes - implements magic "req" and "rsp" members

=head1 SYNOPSIS

	This module is not meant to be used directly.

=head1 DESCRIPTION

POE::Stage::TiedAttributes implements a large chunk of POE::Stage's
magical data scopes.  It's implemented as a tied hash to sequester
its own data and implementation from the end user, leaving $self and
its namespace free for developers.

It holds request-scoped data, which is really stage-scoped data
associated with the request.

It performs necessary cleanup when stages are destroyed or requests
are canceled.

It does these things as automatically as possible.

=head2 $req and $rsp

The $req and $rsp lexical variable is special within message handlers.
The first evaluates to the current POE::Request being handled.  The
second evaluates to the currently emitted or returned response being
handled.

Consider this request:

	my $request = POE::Request->new(
		stage  => $stage_1,
		method => "handle_it",
	);

It will be handled $stage_1's handle_it() method.  For the sake of
example, handle_it() only prints the request object:

	sub handle_it :Handler {
		my $req
		print "$req\n";
	}

To be honest, $req and $request are not required to be identical.  For
example, handle_it() may be executed in a different process, so the
message will be equivalent but not identical.

$req is also great for responding to requests.

	$req->emit( ... );
	$req->return( ... );

See POE::Request for more information about emit() and return().

$req is valid when responses to our own requests are being handled.
This handler cascades a return() from a sub-request to a parent
request.  It's called in response to some request we've previously
made, and in turn it passes a response back up the request tree.

	sub handle_a_response :Handler {
		my $req;
		$req->return(
			type      => "done",
			args      => {
				result  => my $arg_sub_result,  # parameter to this handler
				cookie  => my $req_cookie,      # initialized elsewhere
			},
		);
	}

=head2 $rsp and the $rsp_ closure variables

The special $rsp variable refers to responses to requests made by a
stage.  It's only valid when a response handler is currently
executing.  Here a response object is used to re-call a sub-stage in
response to an emitted interim response.

	sub handle_sub_response :Handler {
		my $rsp;
		$rsp->recall( ... );
	}

Response variables, $rsp_something, are only visible in response
handlers.  They share the same closure as the request that triggered
the response.  Consider the following:

	sub make_a_request :Handler {
		my $req_stage; # a sub-stage
		my $req_stage_request = POE::Request->new(
			stage => $req_stage,
			...,
			on_return => "handle_return",
		);

		expose $req_stage_request, my $anyprefix_cookie;
		my $anyprefix_cookie = "saved in the sub-request closure";
	}

The last two lines expose a member of the newly created request and
store a value into it.  That walue will be available as $rsp_cookie
when a response to $req_stage_request is handled:

	sub handle_return :Handler {
		my $rsp_cookie;  # contains "saved in the sub-request closure"
		...
	}

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
sub _set_req_rsp { $_[0][REQUEST] = $_[1]; $_[0][RESPONSE] = $_[2] }

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

POE::Stage is too young for production use.  For example, its syntax
is still changing.  You probably know what you don't like, or what you
need that isn't included, so consider fixing or adding that, or at
least discussing it with the people on POE's mailing list or IRC
channel.  Your feedback and contributions will bring POE::Stage closer
to usability.  We appreciate it.

=head1 SEE ALSO

L<POE::Stage> and L<POE::Request>.

=head1 AUTHORS

Rocco Caputo <rcaputo@cpan.org>.

=head1 LICENSE

POE::Stage::TiedAttributes is Copyright 2005-2006 by Rocco Caputo.
All rights are reserved.  You may use, modify, and/or distribute this
module under the same terms as Perl itself.

=cut
