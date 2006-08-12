# $Id$

package POE::Member::Hash;

use warnings;
use strict;

use Scalar::Util qw(weaken);
use Carp qw(croak);

use constant ATT_OBJECT  => 0;
use constant ATT_NAME    => 1;

sub TIEHASH {
	my ($class, $object, $att_name) = @_;
	my $self = bless [
		$object,    # ATT_OBJECT
		$att_name,  # ATT_NAME
	], $class;
	weaken $self->[ATT_OBJECT];
	return $self;
}

sub FETCH {
	my ($self, $key) = @_;
	return $self->[ATT_OBJECT]{$self->[ATT_NAME]}->{$key};
}

sub STORE {
	my ($self, $key, $value) = @_;
	return $self->[ATT_OBJECT]{$self->[ATT_NAME]}->{$key} = $value;
}

sub DELETE {
	my ($self, $key) = @_;
	return delete $self->[ATT_OBJECT]{$self->[ATT_NAME]}->{$key};
}

sub CLEAR {
	my ($self) = @_;
	return %{$self->[ATT_OBJECT]{$self->[ATT_NAME]}} = ();
}

sub EXISTS {
	my ($self, $key) = @_;
	return exists $self->[ATT_OBJECT]{$self->[ATT_NAME]}->{$key};
}

sub FIRSTKEY {
	my ($self) = @_;
	# reset each() iterator
	my $a = keys %{$self->[ATT_OBJECT]{$self->[ATT_NAME]}};
	return each %{$self->[ATT_OBJECT]{$self->[ATT_NAME]}};
}

sub NEXTKEY {
	my ($self, $lastkey) = @_;
	return each %{$self->[ATT_OBJECT]{$self->[ATT_NAME]}};
}

sub SCALAR {
	my ($self) = @_;
	return scalar %{$self->[ATT_OBJECT]{$self->[ATT_NAME]}};
}

1;
