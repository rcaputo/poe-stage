# $Id$

=head1 NAME

POE::Stage::TiedAttributes - implements request-scoped data storage

=head1 SYNOPSIS

	This module is not meant to be used directly.

=head1 DESCRIPTION

POE::Requset::TiedAttributes and POE::Stage::TiedAttributes are used
to map hash access in request objects to request-scoped storage in
stage objects.  POE::Request::TiedAttributes describes
request/response continuations.  This document will talk about the
special req and rsp data members of POE::Stage.

=head2 The "req" Data Member

Every POE::Stage object has two read-only data members: req and rsp.
The req data member refers to the POE::Request object that the stage
is currently handling.  For example:

	my $req = POE::Request->new(
		_stage  => $stage_1,
		_method => "handle_it",
	);

Now here's $stage_1's handle_it() method.  When called, it will print
its current request.  That request will be the same as $req, created
above.

	sub handle_it {
		my ($self, $args) = @_;
		print "$self->{req}\n";
	}

Actually, it may not be exactly the same as $req, but it will be the
moral equivalent of $req.  This caveat leaves a loophole through which
we can pass requests across process boundaries later.

$self->{req} is also great for responding to requests:

	$self->{req}->emit( ... );
	$self->{req}->return( ... );

It should be noted that $self->{req} is valid (and, if we're lucky,
correct) when responses to our own requests are being handled.  This
hander cascades a return() from a sub-request to a parent request:

	sub handle_a_response {
		my ($self, $args) = @_;
		$self->{req}->return(
			_type => "done",
			result => $args->{sub_result},
			cookie => $self->{req}{cookie},
		);
	}

=head2 The "rsp" Data Member

The special $self->{rsp} data member refers to responses to requests
we've made.  It's only valid during the execution of methods currently
handling responses.

	sub handle_sub_response {
		my ($self, $args) = @_;
		$self->{rsp}->recall( ... );
	}

When used as a hash, the response in $self->{rsp} refers to the scope
of the request that generated it.

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
		croak "Use \$self->{$1}{$key} = $value instead";
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
