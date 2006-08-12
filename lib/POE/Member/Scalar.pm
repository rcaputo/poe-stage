# $Id$

package POE::Member::Scalar;

use warnings;
use strict;

use Scalar::Util qw(weaken);
use Carp qw(croak);

use constant ATT_OBJECT  => 0;
use constant ATT_NAME    => 1;

sub TIESCALAR {
	my ($class, $object, $att_name) = @_;
	my $self_scalar;
	my $self = bless [
		$object,    # ATT_OBJECT
		$att_name,  # ATT_NAME
	], $class;
	weaken $self->[ATT_OBJECT];
	return $self;
}

sub FETCH {
	my $self = shift;
	return $self->[ATT_OBJECT]{$self->[ATT_NAME]};
}

sub STORE {
	my ($self, $value) = @_;
	return $self->[ATT_OBJECT]{$self->[ATT_NAME]} = $value;
}

1;
