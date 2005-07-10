#!/usr/bin/perl

use warnings;
use strict;

{
	package TiedAttributes;

	# This is so simple.  We could do the bless outside.

	sub TIEHASH {
		my ($class, $fields) = @_;
		my $self = bless $fields, $class;
		return $self;
	}

	sub STORE {
		my ($self, $key, $value) = @_;
		print "$self storing $key = $value\n";
	}
}

{
	package Object;

	sub new {
		my $class = shift;

		tie my (%self), "TiedAttributes", [
			"a",
			"b",
			"c",
		];

		my $self = bless \%self, $class;

		return $self;
	}
}

my $o = Object->new();
print $o, "\n";             # Exposes the Object object.

$o->{moo} = "bar";          # Triggers STORE.

print tied(%$o), "\n";      # Exposes the TiedAttributes object.
