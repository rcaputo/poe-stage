#!/usr/bin/env perl
# $Id$

# An OO form of genlex.perl.  See Persistence.pm for the magic, or
# __END__ for sample output.

use warnings;
use strict;

use Persistence;

# A handy target to show off persistence and not.

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

	foreach my $number (qw(one two three four five)) {
		$persistence->call(\&target, number => $number);
	}
}

### Create a context, and wrap a function call in it.  

{
	print "The wrap() way:\n";

	my $persistence = Persistence->new();
	my $thunk = $persistence->wrap(\&target);

	foreach my $number (qw(one two three four five)) {
		$thunk->(number => $number);
	}
}

### Subclass to handle some of POE's function call argument rules.

{
	package PoeLex;
	our @ISA = qw(Persistence);
	use Scalar::Util qw(weaken);

	# TODO - Make these lazy so the work isn't done every call?

	sub set_arg_context {
		my $self = shift;
		use POE::Session;
		my %param = map { $_ - ARG0, $_[$_] } (ARG0..$#_);
		$self->set_context(arg => \%param);

		# Modify the catch-all context so it contains other arguments.

		my $catch_all = $self->get_context("_");
		weaken($catch_all->{kernel} = $_[KERNEL]);
		weaken($catch_all->{session} = $_[SESSION]);
		weaken($catch_all->{sender} = $_[SENDER]);
	}
}

### Wrap a POE handler in PoeLex.

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

	# Here's a sample handler with persistence.  $arg_0 has been aliased
	# to $_[ARG0].  $heap_foo has been aliased to $_[HEAP]{foo}.

	sub handle_moo {
		my $arg_0++;     # magic
		my $heap_foo++;  # more magic
		my $kernel;      # also magic

		print "  count = $arg_0 ... heap = $heap_foo ... heap b = $_[HEAP]{foo}\n";
		$kernel->yield(moo => $arg_0) if $arg_0 < 10;
	}
}

exit;

__END__

The call() way:
	target arg_number(one) narf_x(1) _i(1) j(1)
	target arg_number(two) narf_x(2) _i(1) j(2)
	target arg_number(three) narf_x(3) _i(1) j(3)
	target arg_number(four) narf_x(4) _i(1) j(4)
	target arg_number(five) narf_x(5) _i(1) j(5)
The wrap() way:
	target arg_number(one) narf_x(1) _i(1) j(1)
	target arg_number(two) narf_x(2) _i(1) j(2)
	target arg_number(three) narf_x(3) _i(1) j(3)
	target arg_number(four) narf_x(4) _i(1) j(4)
	target arg_number(five) narf_x(5) _i(1) j(5)
Using POE:
	count = 1 ... heap = 1 ... heap b = 1
	count = 2 ... heap = 2 ... heap b = 2
	count = 3 ... heap = 3 ... heap b = 3
	count = 4 ... heap = 4 ... heap b = 4
	count = 5 ... heap = 5 ... heap b = 5
	count = 6 ... heap = 6 ... heap b = 6
	count = 7 ... heap = 7 ... heap b = 7
	count = 8 ... heap = 8 ... heap b = 8
	count = 9 ... heap = 9 ... heap b = 9
	count = 10 ... heap = 10 ... heap b = 10
