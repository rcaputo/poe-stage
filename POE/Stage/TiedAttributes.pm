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

	return $self->[REQUEST]  = $value if $key eq "req";
	return $self->[RESPONSE] = $value if $key eq "rsp";

	if ($key =~ /^req_/) {
		croak "Cannot store '$key' outside of a request" unless $self->[REQUEST];
		return $self->[REQUEST]->_get_context()->{$key} = $value;
	}

	if ($key =~ /^rsp_/) {
		croak "Cannot store '$key' outside of a response" unless $self->[RESPONSE];
		die "Not sure how to define response contexts";
		return $self->[RESPONSE]->_get_context()->{$key} = $value;
	}

	return $self->[STAGE_DATA]{$key} = $value;
}

sub FETCH {
	my ($self, $key) = @_;

	return $self->[REQUEST]  if $key eq "req";
	return $self->[RESPONSE] if $key eq "rsp";

	if ($key =~ /^req_/) {
		croak "Attempting to fetch '$key' from outside a request" unless (
			$self->[REQUEST]
		);
		return $self->[REQUEST]->_get_context()->{$key};
	}

	if ($key =~ /^rsp_/) {
		croak "Attempting to fetch '$key' from outside a response" unless (
			$self->[RESPONSE]
		);
		die "Not sure how to define response contexts";
		return $self->[RESPONSE]->_get_context()->{$key};
	}

	return $self->[STAGE_DATA]{$key};
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
		push @keys, "req", keys(%$context);
		push @keys, "rsp" if $self->[RESPONSE];
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

	return defined $self->[REQUEST]  if $key eq "req";
	return defined $self->[RESPONSE] if $key eq "rsp";

	if ($key =~ /^req_/) {
		croak "Cannot tests existence of '$key' outside of a request" unless (
			$self->[REQUEST]
		);
		return exists $self->[REQUEST]->_get_context()->{$key};
	}

	if ($key =~ /^rsp_/) {
		croak "Cannot tests existence of '$key' outside of a response" unless (
			$self->[RESPONSE]
		);
		die "Not sure how to define response contexts";
		return exists $self->[RESPONSE]->_get_context()->{$key};
	}

	return exists $self->[STAGE_DATA]{$key};
}

sub DELETE {
	my ($self, $key) = @_;

	# TODO - Can we use the newfangled delete-on-array here?
	if ($key eq "req") {
		my $old_val = $self->[REQUEST];
		$self->[REQUEST] = undef;
		return $old_val;
	}

	# TODO - Can we use the newfangled delete-on-array here?
	if ($key eq "rsp") {
		my $old_val = $self->[RESPONSE];
		$self->[RESPONSE] = undef;
		return $old_val;
	}

	# TODO - Some things should not be deletable in some contexts.

	if ($key =~ /^req_/) {
		croak "Cannot delete '$key' outside of a request" unless $self->[REQUEST];
		return delete $self->[REQUEST]->_get_context()->{$key};
	}

	if ($key =~ /^rsp_/) {
		croak "Cannot delete '$key' outside of a response" unless $self->[RESPONSE];
		die "Not sure how to define response contexts";
		return delete $self->[RESPONSE]->_get_context()->{$key};
	}

	return delete $self->[STAGE_DATA]{$key};
}

1;
