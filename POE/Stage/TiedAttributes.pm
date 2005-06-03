# $Id$

# Tied interface to a Stage's data.  Used to transparently fetch
# contextual data for members with a leading underscore ("_foo").

package POE::Stage::TiedAttributes;

use warnings;
use strict;

use Carp qw(croak);

sub SELF_DATA     () { 0 }  # Out-of-band data for POE::Stage.
sub STAGE_DATA    () { 1 }  # Subclass data members.
sub COMBINED_KEYS () { 2 }  # Temporary space for iteration.
sub REQUEST       () { 3 }  # Currently active request.
sub RESPONSE      () { 4 }  # Currently active response.

sub TIEHASH {
	my $class = shift;
	my $self = bless [
		{ },    # SELF_DATA
		{ },    # STAGE_DATA
		[ ],    # COMBINED_KEYS
		undef,  # REQUEST
		undef,  # RESPONSE
	], $class;
	return $self;
}

sub STORE {
	my ($self, $key, $value) = @_;

	return $self->[SELF_DATA]{$key}  = $value if     $key =~ /^__/;
	return $self->[STAGE_DATA]{$key} = $value unless $key =~ /^_/;

	return $self->[REQUEST]  = $value if $key eq "_req";
	return $self->[RESPONSE] = $value if $key eq "_rsp";
	croak "Cannot store '$key' outside of a request" unless $self->[REQUEST];

	return $self->[REQUEST]->_get_context()->{$key} = $value;
}

sub FETCH {
	my ($self, $key) = @_;

	return $self->[SELF_DATA]{$key}  if     $key =~ /^__/;
	return $self->[STAGE_DATA]{$key} unless $key =~ /^_/;

	croak "Attempting to fetch '$key' from outside a request" unless (
		$self->[REQUEST]
	);

	return $self->[REQUEST]  if $key eq "_req";
	return $self->[RESPONSE] if $key eq "_rsp";
	return $self->[REQUEST]->_get_context()->{$key};
}

sub FIRSTKEY {
	my $self = shift;

	my @keys;

	{ my $a = keys %{$self->[STAGE_DATA]};
		push @keys, keys %{$self->[STAGE_DATA]};
	}

	if ($self->[REQUEST]) {
		my $context = $self->[REQUEST]->_get_context();
		my $a = keys %$context;
		push @keys, "_req", keys(%$context);
		push @keys, "_rsp" if $self->[RESPONSE];
	}

	$self->[COMBINED_KEYS] = [ sort @keys ];
	return shift @{$self->[COMBINED_KEYS]};
}

sub NEXTKEY {
	my $self = shift;
	return shift @{$self->[COMBINED_KEYS]};
}

sub EXISTS {
	my ($self, $key) = @_;

	return exists $self->[SELF_DATA]{$key}  if     $key =~ /^__/;
	return exists $self->[STAGE_DATA]{$key} unless $key =~ /^_/;
	return defined $self->[REQUEST]  if $key eq "_req";
	return defined $self->[RESPONSE] if $key eq "_rsp";

	return exists $self->[REQUEST]->_get_context()->{$key};
}

sub DELETE {
	my ($self, $key) = @_;

	# TODO - Some things should not be deletable in some contexts.

	return delete $self->[SELF_DATA]{$key}  if     $key =~ /^__/;
	return delete $self->[STAGE_DATA]{$key} unless $key =~ /^_/;

	# TODO - Can we use the newfangled delete-on-array here?
	if ($key eq "_req") {
		my $old_val = $self->[REQUEST];
		$self->[REQUEST] = undef;
		return $old_val;
	}

	# TODO - Can we use the newfangled delete-on-array here?
	if ($key eq "_rsp") {
		my $old_val = $self->[RESPONSE];
		$self->[RESPONSE] = undef;
		return $old_val;
	}

	return delete $self->[REQUEST]->_get_context()->{$key};
}

1;
