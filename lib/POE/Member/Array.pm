# $Id$

package POE::Member::Array;

use warnings;
use strict;

use Scalar::Util qw(weaken);
use Carp qw(croak);

use constant ATT_OBJECT  => 0;
use constant ATT_NAME    => 1;

sub TIEARRAY {
	my ($class, $object, $att_name) = @_;
	my $self = bless [
		$object,    # ATT_OBJECT
		$att_name,  # ATT_NAME
	], $class;
	weaken $self->[ATT_OBJECT];
	return $self;
}

sub FETCH {
	my ($self, $index) = @_;
	return $self->[ATT_OBJECT]{$self->[ATT_NAME]}->[$index];
}

sub STORE {
	my ($self, $index, $value) = @_;
	return $self->[ATT_OBJECT]{$self->[ATT_NAME]}->[$index] = $value;
}

sub FETCHSIZE {
	my ($self) = @_;
	return scalar @{$self->[ATT_OBJECT]{$self->[ATT_NAME]}};
}

sub STORESIZE {
	my ($self, $size) = @_;
	return $#{$self->[ATT_OBJECT]{$self->[ATT_NAME]}} = $size - 1;
}

sub CLEAR {
	my ($self) = @_;
	return @{$self->[ATT_OBJECT]{$self->[ATT_NAME]}} = ();
}

sub POP {
	my ($self) = @_;
	return pop @{$self->[ATT_OBJECT]{$self->[ATT_NAME]}};
}

sub PUSH {
	my $self = shift;
	return push @{$self->[ATT_OBJECT]{$self->[ATT_NAME]}}, @_;
}

sub SHIFT {
	my ($self) = @_;
	return shift @{$self->[ATT_OBJECT]{$self->[ATT_NAME]}};
}

sub UNSHIFT {
	my $self = shift;
	return unshift @{$self->[ATT_OBJECT]{$self->[ATT_NAME]}}, @_;
}

sub EXISTS {
	my ($self, $index) = @_;
	return exists $self->[ATT_OBJECT]{$self->[ATT_NAME]}->[$index];
}

sub DELETE {
	my ($self, $index) = @_;
	return delete $self->[ATT_OBJECT]{$self->[ATT_NAME]}->[$index];
}

sub SPLICE {
	my $self = shift;
	my $offset = @_ ? shift : 0;

	$offset += @{$self->[ATT_OBJECT]{$self->[ATT_NAME]}} if $offset < 0;
	my $length = @_ ? shift : @{$self->[ATT_OBJECT]{$self->[ATT_NAME]}} - $offset;
	return splice @{$self->[ATT_OBJECT]{$self->[ATT_NAME]}}, $offset, $length, @_;
}

sub EXTEND { }

1;
