#!perl
# $Id$

# Experiment to replace @_ use with attributes denoting "self",
# subroutine arguments, and data members.

{
	package Moo;

	use warnings;
	use strict;
	use base qw(SweetAtUnder);

	sub new {
		my $class :Self;
		my ($init_1, $init_2) :Arg;

		warn "class($class) new( init_1 => '$init_1', init_2 => '$init_2')\n";

		return bless { member => "($init_1) ($init_2)" }, $class;
	}

	sub method {
		my $self :Self;
		my $member :Memb;

		warn "Invoked $self -> method() ... has member($member)\n";
	}
}

my $moo = Moo->new({ init_1 => "testing 123", init_2 => "testing abc" });
$moo->method();

exit;
