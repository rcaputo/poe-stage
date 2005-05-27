# $Id$

# Tied interface to a Stage's data.  Used to transparently fetch
# contextual data for members with a leading underscore ("_foo").

package TiedStage;

use warnings;
use strict;

sub SELF_DATA     () { 0 }
sub STAGE_DATA    () { 1 }
sub COMBINED_KEYS () { 2 }

sub TIEHASH {
	my $class = shift;
	my $self = bless [
		{ },  # SELF_DATA
		{ },  # STAGE_DATA
		[ ],  # COMBINED_KEYS
	], $class;
	return $self;
}

sub STORE {
	my ($self, $key, $value) = @_;

	return $self->[SELF_DATA]{$key}  = $value if     $key =~ /^__/;
	return $self->[STAGE_DATA]{$key} = $value unless $key =~ /^_/;

	my $context = Call->_get_current_context();
	return $context->{$key} = $value;
}

sub FETCH {
	my ($self, $key) = @_;

	return $self->[SELF_DATA]{$key}  if     $key =~ /^__/;
	return $self->[STAGE_DATA]{$key} unless $key =~ /^_/;

	my $context = Call->_get_current_context();
	return $context->{$key};
}

sub FIRSTKEY {
	my $self = shift;

	my @keys;

	{ my $a = keys %{$self->[STAGE_DATA]};
		push @keys, keys %{$self->[STAGE_DATA]};
	}

	{ my $context = Call->_get_current_context();
		my $a = keys %$context;
		push @keys, keys %$context;
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

	my $context = Call->_get_current_context();
	return exists $context->{$key};
}

1;
