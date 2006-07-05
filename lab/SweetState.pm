# $Id$

# Sweet run state classes.

package SweetState;

use warnings;
use strict;

use Attribute::Handlers;
use PadWalker qw(var_name);
use Scalar::Util qw(blessed reftype);
use Carp qw(croak);

sub Req :ATTR {
	my ($pkg, $sym, $ref, $attr, $data, $phase) = @_;
	#warn "pkg($pkg) sym($sym) ref($ref) attr($attr) data($data) phase($phase)\n";

	croak "can't register blessed things as Request fields" if blessed($ref);

	my $type = reftype($ref);
	my $name = var_name(4, $ref);

	# TODO - To make this work tidily, we should translate $name into a
	# reference to the proper request/response field and pass that into
	# the tie handler.  Then the tied variable can work directly with
	# the field, or perhaps a weak copy of it.

	if ($type eq "SCALAR") {
		return tie $$ref, "TiedScalar", $name;
	}

	if ($type eq "HASH") {
		return tie %$ref, "TiedHash", $name;
	}

	if ($type eq "ARRAY") {
		return tie @$ref, "TiedArray", $name;
	}

	croak "can't register $type as a Request field";
}

# Tie magic.

{
	package TiedScalar;

	sub TIESCALAR {
		my ($class, $name) = @_;
		return bless [ $name, undef ], $class;
	}

	sub FETCH {
		my $self = shift;
		warn "fetch: $self->[0]\n";
		return $self->[1];
	}

	sub STORE {
		my ($self, $value) = @_;
		warn "store: $self->[0] = $value\n";
		return $self->[1] = $value;
	}
}

{
	package TiedArray;

	sub EXTEND { }

	sub FETCHSIZE {
		my $self = shift;
		return scalar @{$self->[1]};
	}

	sub TIEARRAY {
		my ($class, $name) = @_;
		return bless [ $name, [] ], $class;
	}

	sub CLEAR {
		my $self = shift;
		warn "clear: $self->[0]\n";
		return $self->[1] = [ ];
	}

	sub FETCH {
		my ($self, $index) = @_;
		warn "fetch: '$self->[0]'\[$index\]\n";
		return $self->[1][$index];
	}

	sub STORE {
		my ($self, $index, $value) = @_;
		warn "store: '$self->[0]'\[$index\] = $value\n";
		return $self->[1][$index] = $value;
	}
}

{
	package TiedHash;

	sub TIEHASH {
		my ($class, $name) = @_;
		return bless [ $name, {} ], $class;
	}

	sub CLEAR {
		my $self = shift;
		warn "clear: $self->[0]\n";
		return $self->[1] = { };
	}

	sub FETCH {
		my ($self, $key) = @_;
		warn "fetch: $self->[0]\{$key\}\n";
		return $self->[1]{$key};
	}

	sub STORE {
		my ($self, $key, $value) = @_;
		warn "store: $self->[0]\{$key\} = $value\n";
		return $self->[1]{$key} = $value;
	}
}

1;
