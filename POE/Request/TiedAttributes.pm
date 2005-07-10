# $Id$

# Tied interface to a POE::Request's context.  Used to provide an
# unrestricted, hash-like interface to the request's scope without
# clashing with the request object's internal data.

package POE::Request::TiedAttributes;

use warnings;
use strict;

use Carp qw(croak);

use constant REQ_CONTEXT => 10;  # This request's context.

sub TIEHASH {
	my ($class, $self) = @_;
	return bless $self, $class;
}

sub STORE {
	my ($self, $key, $value) = @_;
	return $self->[REQ_CONTEXT]{$key} = $value;
}

sub FETCH {
	my ($self, $key) = @_;
	return $self->[REQ_CONTEXT]{$key};
}

sub FIRSTKEY {
	my $self = shift;
	my $a = keys %{$self->[REQ_CONTEXT]};   # Reset each() iterator.
	return each %{$self->[REQ_CONTEXT]};
}

sub NEXTKEY {
	my $self = shift;
	return each %{$self->[REQ_CONTEXT]};
}

sub EXISTS {
	my ($self, $key) = @_;
	return exists $self->[REQ_CONTEXT]{$key};
}

sub DELETE {
	my ($self, $key) = @_;
	return delete $self->[REQ_CONTEXT]{$key};
}

1;
