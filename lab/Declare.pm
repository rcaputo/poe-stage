# $Id$

# Support
#
#   declare my $scalar = $value;
#   declare my $scalar;
#   declare my ($scalar, $scalar) = ($val1, $val2);
#   declare my ($a, $b), my($c, $d);
#   ...
#
# See declare.perl for sample applications.
#
# CAVEAT: Only scalars may be declared.  I'm not sure how to declare
# arrays since the members of declare()'s @_ are aliases to the values
# in the array, not the variable being declared.  var_name() therefore
# can't find the variable name.

package Declare;

use warnings;
use strict;

use PadWalker qw(var_name);
use Exporter;
use base qw(Exporter);
our @EXPORT = qw(declare declare_a declare_u);

sub declare (@) {
	print "declare() called with:\n";
	for (my $i = 0; $i < @_; $i++) {
		my $val = $_[$i];
		$val = "(undef)" unless defined $val;
		$val = "(empty)" unless length $val;

		print "  var $i (", \$_[$i], "): ", var_name(1, \$_[$i]), " = $val\n";

		# The intended application:
		#   Remove the sigil, and hang onto it.
		#   If the variable matches /^arg_/, then do the :Arg magic.
		#   If it matches /^req_/, then do :Req magic.
		#   If it's "$" . "self", then do :Self magic.
		#   etc.
	}
}

# Philip Gwyn's array declaration.
#
# This works, with one simple but (to me) annoying caveat: Unlike
# my() and declare(), declare_a() only works on a single variable at a
# time.  These are illegal:
#
#   declare( my (@a, @b );
#   declare my @a, my @b;
#   declare my $scalar, my @array;
#
# We also can't say this because the first argument to declare_a()
# becomes a "list assignment":
#
#   declare my @array = qw(list1 list2 list3);

sub declare_a (\@) {
	print "declare_a() called:\n";

	# Try lexicals first.

	my $var_name = var_name(1, $_[0]);

	# Try globals.
	# This is an interesting variant of declare().  Is it useful?

	unless ($var_name) {
		my $vars = peek_our( 1 );
		while( my( $name, $reference ) = each %$vars ) {
			next unless $reference == $_[0];
			$var_name = $name;
			last;
		}
	}

	print "  var 0 $var_name = (@{$_[0]})\n";
}

# Matt Trout suggested the \[$@%] prototype syntax, which I had never
# heard of before.  But it's documented.  Here's an attempt at it.
# FIXME - I wish there were a "varargs" modifier to prototypes, to say
# "and zero or more of this".  Until there is one, extend the
# prototype as far as necessary.

sub declare_u (\[$@%];\[$@%]\[$@%]\[$@%]\[$@%]\[$@%]\[$@%]\[$@%]\[$@%]\[$@%]\[$@%]\[$@%]\[$@%]\[$@%]\[$@%]\[$@%]\[$@%]\[$@%]\[$@%]\[$@%]) {
	print "declare_u() called with:\n";
	for (my $i = 0; $i < @_; $i++) {
		my $ref = $_[$i];

		my $val;
		if (ref($_[$i] eq "SCALAR")) {
			$val = $$ref;
		}
		elsif (ref($_[$i] eq "ARRAY")) {
			$val = "@$ref";
		}
		elsif (ref($_[$i] eq "HASH")) {
			$val = join "; ", map { "$_ = $ref->{$_}" } keys %$ref;
		}

		$val = "(undef)" unless defined $val;
		$val = "(empty)" unless length $val;

		print "  var $i (", $ref, "): ", var_name(1, $ref), " = $val\n";
	}
}

1;
