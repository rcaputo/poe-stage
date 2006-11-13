#!/usr/bin/env perl
# $Id$

# An OO form of genlex.perl.  See Persistence.pm for the magic.

use warnings;
use strict;

use Persistence;

### A handy target to show off persistence and not.

sub target {
	my $arg_number;   # Parameter.
	my $narf_x++;     # Persistent.
	my $_i++;         # Dynamic.
	my $j++;          # Persistent.

	print "  target arg_number($arg_number) narf_x($narf_x) _i($_i) j($j)\n";
}

### Create a context, and call something within it.

{
	print "The call() way:\n";

	my $persistence = Persistence->new();
	$persistence->set_context( _ => { } );

	foreach my $number (qw(one two three four five)) {
		$persistence->call(\&target, number => $number);
	}
}

### Wrap a function and call it as usual.

{
	print "The wrap() way:\n";

	my $persistence = Persistence->new();

	my $thunk = $persistence->wrap(\&target);
	foreach my $number (qw(one two three four five)) {
		$thunk->(number => $number);
	}
}

### Now with POE, just to see if we can.

{
	package PoeLex;
	our @ISA = qw(Persistence);

	sub generate_arg_hash {
		my $self = shift;
		package DB;
		my @x = caller(2);
		use POE::Session;
		my %param = map { $_ - ARG0, $DB::args[$_] } (ARG0..$#DB::args);
		return arg => \%param;
	}
}

{
	print "Using POE:\n";

	use POE;
	spawn();
	POE::Kernel->run();

	sub spawn {
		my $persistence = PoeLex->new();

		my %heap;
		$persistence->set_context( heap => \%heap );

		POE::Session->create(
			heap => \%heap,
			inline_states => {
				_start => sub { $_[KERNEL]->yield(moo => 0) },
				moo    => $persistence->wrap(\&handle_moo),
			},
		);
	}

	sub handle_moo {
		my $arg_0++;     # magic
		my $heap_foo++;  # more magic

		print "  count = $arg_0 ... heap = $heap_foo ... heap b = $_[HEAP]{foo}\n";
		$_[KERNEL]->yield(moo => $arg_0) if $arg_0 < 10;
	}
}

exit;
