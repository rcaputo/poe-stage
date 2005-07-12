# $Id$

# Tied interface to a Stage's data.  Used to transparently fetch
# contextual data for members with a leading underscore ("_foo").

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
