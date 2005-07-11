#!/usr/bin/perl
# $Id$

# Experiment with object stringification.  This is so we can have
# different POE::Reference objects overlap at the appropriate $self
# keys.

use warnings;
use strict;

{
	package Object;

	use overload '""' => sub {
		my $self = shift;
		return $self->{id};
	};

	sub new {
		my $class = shift;
		return bless {
			id => 31415,
		}, $class;
	}

	sub is_equal_to {
		my ($self, $other) = @_;
		return $self == $other;
	}
}

my $obj = Object->new;
print "$obj\n";

my %hash;
$hash{$obj} = $obj;

warn ref($hash{$obj});

use Data::Dumper qw(Dumper);
warn Dumper \%hash;

print "not " unless $obj->is_equal_to($obj);
print "equal\n";
