# $Id$

=head1 NAME

POE::Stage::TiedAttributes - internal class for request-scoped storage

=head1 SYNOPSIS

	This module is not meant to be used directly.

=head1 DESCRIPTION

POE::Stage::TiedAttributes implements a large chunk of POE::Stage's
magical data scopes.

It manages the special $self->{req} and $self->{rsp} fields.  They
will always point to the proper POE::Request objects.

It holds request-scoped data, which is really stage-scoped data
associated with the request.

It performs necessary cleanup when stages are destroyed or requests
are canceled.

It does these things as automatically as possible.

=head2 POE::Stage's "req" Data Member

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
pass requests across process boundaries later.

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
		$self->{req}->return(
			type      => "done",
			args      => {
				result  => $args->{sub_result},
				cookie  => $self->{req}{cookie},
			},
		);
	}

=head2 POE::Stage's "rsp" Data Member

The special $self->{rsp} data member refers to responses to requests
made by a stage.  It's only valid when a response handler is currently
executing.

	sub handle_sub_response {
		my ($self, $args) = @_;
		$self->{rsp}->recall( ... );
	}

When used as a hash, the response in $self->{rsp} refers to the scope
of the request that generated it.  Therefore you can store data in the
original request and automatically have access to it from the response
handler.

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

sub STORE {
	my ($self, $key, $value) = @_;

	# For debugging during the transition from $stage->{req_foo} to
	# $stage->{req}{foo} syntax.
	if ($key =~ s/^(req|rsp)_//) {
		croak "Use :Req or :Rsp attributes instead";
	}

	croak "$key is a read-only data member" if $key eq "req" or $key eq "rsp";
	return $self->[STAGE_DATA]{$key} = $value;
}

sub FETCH {
	my ($self, $key) = @_;
	return $self->[REQUEST]  if $key eq "req";
	return $self->[RESPONSE] if $key eq "rsp";
	return $self->[STAGE_DATA]{$key};
}

sub FIRSTKEY {
	my $self = shift;

	my @keys;

	{ my $a = keys %{$self->[STAGE_DATA]};
		push @keys, keys %{$self->[STAGE_DATA]};
	}

	push @keys, "req" if $self->[REQUEST];
	push @keys, "rsp" if $self->[RESPONSE];

	$self->[COMBINED_KEYS] = [ sort @keys ];
	return shift @{$self->[COMBINED_KEYS]};
}

sub NEXTKEY {
	my $self = shift;
	return shift @{$self->[COMBINED_KEYS]};
}

sub EXISTS {
	my ($self, $key) = @_;
	return defined $self->[REQUEST]  if $key eq "req";
	return defined $self->[RESPONSE] if $key eq "rsp";
	return exists $self->[STAGE_DATA]{$key};
}

sub DELETE {
	my ($self, $key) = @_;
	croak "$key is a read-only data member" if $key eq "req" or $key eq "rsp";
	return delete $self->[STAGE_DATA]{$key};
}

sub _request_context_store {
	my ($self, $req_id,$key, $value) = @_;
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

See http://thirdlobe.com/projects/poe-stage/report/1 for known issues.
See http://thirdlobe.com/projects/poe-stage/newticket to report one.

=head1 SEE ALSO

POE::Request::TiedAttributes, which implements the POE::Request side
of this magic and discusses the request-scoped namespaces in a little
more detail.

=head1 AUTHORS

Rocco Caputo <rcaputo@cpan.org>.

=head1 LICENSE

POE::Stage::TiedAttributes is Copyright 2005 by Rocco Caputo.  All
rights are reserved.  You may use, modify, and/or distribute this
module under the same terms as Perl itself.

=cut
