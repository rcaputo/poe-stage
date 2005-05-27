#!/usr/bin/perl
# vim: filetype=perl

# Test synchronous objects.
# Ensure they're called properly.
# Ensure they're destroyed properly.

use warnings;
use strict;
use Test::More qw(no_plan);

{ package Sync;
	use base qw(Stage);

	sub init {
		my ($self, $call) = @_;
		$self->{name} = $call->{name};
	}

	sub name {
		my $self = shift;
		return $self->{name};
	}

	sub DESTROY {
		my $self = shift;
		warn "destroying $self";
	}
}

my @o;
foreach my $name (qw(one two three four five)) {
	push @o, Sync->new( name => $name );
}

while (@o) {
	print shift(@o)->name(), "\n";
}

exit;
