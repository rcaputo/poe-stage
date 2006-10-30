# $Id$

# Support
#
#   init my $scalar = $value;
#   declare my $scalar;
#   init my ($scalar, $scalar) = ($val1, $val2);
#   declare my ($a, $b), my($c, $d);
#   declare my @a, my $b, my %c;
#   ...
#
# See declare.perl for sample applications.
#
# Summary: There are two declarators, declare() and init().  Declare()
# can declare nonscalar types, but you can't initialize them.  init()
# can initialize scalars, but you can't declare nonscalars.
#
# Why one function can't do both:  The (@) type flattens its
# parameters, so @_ within the called function contains elements from
# arrays and hashes passed to the function.  The function can't
# determine with any accuracy what the original variables were.  Matt
# Trout suggested Devel::Caller, but as of this time it can't handle
# more complex declarations.
#
# Meanwhile the (\[$@%]) prototype can't handle assignments.  You
# can't say "declare my $x = 1" because it throws an error about
# calling declare() with an assignment.
#
# The current compromise is to implement two forms of declarator:
# declare() that handles any variable type but no initialization, and
# init() that allows initialization, but only for scalars.  It's not
# perfect, but at least we get two functions with reasonably
# understandable names.

# We can't have $object->declare( my $x ) because prototypes are
# necessary for declare(), and Perl doesn't honor them for method
# calls.

package Declare;

use warnings;
use strict;

use Carp qw(croak);
use PadWalker qw(var_name peek_our);
use Exporter;
use base qw(Exporter);
our @EXPORT = qw(init declare members prefixed);

sub init (@) {
	print "init() called with:\n";
	for (my $i = 0; $i < @_; $i++) {
		my $var_reference = \$_[$i];

		my $var_value;
		if (ref($var_reference) eq "SCALAR") {
			$var_value = $$var_reference;
		}
		elsif (ref($var_reference) eq "ARRAY") {
			$var_value = "@$var_reference";
		}
		elsif (ref($var_reference) eq "HASH") {
			$var_value = (
				join "; ",
				map { "$_ = $var_reference->{$_}" }
				keys %$var_reference
			);
		}

		$var_value = "(undef)" unless defined $var_value;
		$var_value = "(empty)" unless length $var_value;

		# Try lexicals first.

		my $var_name = var_name(1, $var_reference);

		# Try globals.  This is from Philip Gwyn's declare_a().
		# This is an interesting variant of declare().  Is it useful?

		unless ($var_name) {
			my $vars = peek_our( 1 );
			while( my( $name, $reference ) = each %$vars ) {
				next unless $reference == $var_reference;
				$var_name = $name;
				last;
			}
		}

		print "  var $i ($var_reference): $var_name = $var_value\n";

		# The intended application:
		#   Remove the sigil, and hang onto it.
		#   If the variable matches /^arg_/, then do the :Arg magic.
		#   If it matches /^req_/, then do :Req magic.
		#   If it's "$" . "self", then do :Self magic.
		#   etc.
	}
}

# Matt Trout suggested the \[$@%] prototype syntax, which I had never
# heard of before.  But it's documented, so cool.
# FIXME - I wish there were a "varargs" modifier to prototypes, to say
# "and zero or more of this".  Until there is one, extend the
# prototype as far as necessary.

sub declare (\[$@%];\[$@%]\[$@%]\[$@%]\[$@%]\[$@%]\[$@%]\[$@%]\[$@%]\[$@%]\[$@%]\[$@%]\[$@%]\[$@%]\[$@%]\[$@%]\[$@%]\[$@%]\[$@%]\[$@%]\[$@%\[$@%\[$@%]]]\[$@%]) {
	print "declare() called with:\n";
	for (my $i = 0; $i < @_; $i++) {
		my $var_reference = $_[$i];

		my $var_value;
		if (ref($var_reference) eq "SCALAR") {
			$var_value = $$var_reference;
		}
		elsif (ref($var_reference) eq "ARRAY") {
			$var_value = "@$var_reference";
		}
		elsif (ref($var_reference) eq "HASH") {
			$var_value = (
				join "; ",
				map { "$_ = $var_reference->{$_}" }
				keys %$var_reference
			);
		}

		$var_value = "(undef)" unless defined $var_value;
		$var_value = "(empty)" unless length $var_value;

		# Try lexicals first.

		my $var_name = var_name(1, $var_reference);

		# Try globals.  This is from Philip Gwyn's declare_a().
		# This is an interesting variant of declare().  Is it useful?

		unless ($var_name) {
			my $vars = peek_our( 1 );
			while( my( $name, $reference ) = each %$vars ) {
				next unless $reference == $var_reference;
				$var_name = $name;
				last;
			}
		}

		print "  var $i ($var_reference): $var_name = $var_value\n";

		# The intended application:
		#   Remove the sigil, and hang onto it.
		#   If the variable matches /^arg_/, then do the :Arg magic.
		#   If it matches /^req_/, then do :Req magic.
		#   If it's "$" . "self", then do :Self magic.
		#   etc.
	}
}

#####

sub members ($\[$@%];\[$@%]\[$@%]\[$@%]\[$@%]\[$@%]\[$@%]\[$@%]\[$@%]\[$@%]\[$@%]\[$@%]\[$@%]\[$@%]\[$@%]\[$@%]\[$@%]\[$@%]\[$@%]\[$@%]\[$@%\[$@%\[$@%]]]\[$@%]) {
	print "members() called with:\n";
	print "  object: $_[0]\n";

	for (my $i = 1; $i < @_; $i++) {
		my $var_reference = $_[$i];

		my $var_value;
		if (ref($var_reference) eq "SCALAR") {
			$var_value = $$var_reference;
		}
		elsif (ref($var_reference) eq "ARRAY") {
			$var_value = "@$var_reference";
		}
		elsif (ref($var_reference) eq "HASH") {
			$var_value = (
				join "; ",
				map { "$_ = $var_reference->{$_}" }
				keys %$var_reference
			);
		}

		$var_value = "(undef)" unless defined $var_value;
		$var_value = "(empty)" unless length $var_value;

		# Try lexicals first.

		my $var_name = var_name(1, $var_reference);

		# Try globals.  This is from Philip Gwyn's declare_a().
		# This is an interesting variant of declare().  Is it useful?

		unless ($var_name) {
			my $vars = peek_our( 1 );
			while( my( $name, $reference ) = each %$vars ) {
				next unless $reference == $var_reference;
				$var_name = $name;
				last;
			}
		}

		print "  var $i ($var_reference): $var_name = $var_value\n";

		# The intended application:
		#   Remove the sigil, and hang onto it.
		#   If the variable matches /^arg_/, then do the :Arg magic.
		#   If it matches /^req_/, then do :Req magic.
		#   If it's "$" . "self", then do :Self magic.
		#   etc.
	}
}

###

sub prefixed ($\[$@%];\[$@%]\[$@%]\[$@%]\[$@%]\[$@%]\[$@%]\[$@%]\[$@%]\[$@%]\[$@%]\[$@%]\[$@%]\[$@%]\[$@%]\[$@%]\[$@%]\[$@%]\[$@%]\[$@%]\[$@%\[$@%\[$@%]]]\[$@%]) {
	print "prefixed() called with:\n";
	print "  object: $_[0]\n";

	for (my $i = 1; $i < @_; $i++) {
		my $var_reference = $_[$i];

		my $var_value;
		if (ref($var_reference) eq "SCALAR") {
			$var_value = $$var_reference;
		}
		elsif (ref($var_reference) eq "ARRAY") {
			$var_value = "@$var_reference";
		}
		elsif (ref($var_reference) eq "HASH") {
			$var_value = (
				join "; ",
				map { "$_ = $var_reference->{$_}" }
				keys %$var_reference
			);
		}

		$var_value = "(undef)" unless defined $var_value;
		$var_value = "(empty)" unless length $var_value;

		# Try lexicals first.

		my $var_name = var_name(1, $var_reference);
		my $field_name = $var_name;
		unless ($field_name =~ s/^(.)_*[^_]+_/$1/) {
			croak "Variable $var_name has no prefix";
		}

		# Try globals.  This is from Philip Gwyn's declare_a().
		# This is an interesting variant of declare().  Is it useful?

		unless ($var_name) {
			my $vars = peek_our( 1 );
			while( my( $name, $reference ) = each %$vars ) {
				next unless $reference == $var_reference;
				$var_name = $name;
				last;
			}
		}

		print(
			"  var $i ($var_reference): $var_name (from $field_name) = $var_value\n"
		);

		# The intended application:
		#   Remove the sigil, and hang onto it.
		#   If the variable matches /^arg_/, then do the :Arg magic.
		#   If it matches /^req_/, then do :Req magic.
		#   If it's "$" . "self", then do :Self magic.
		#   etc.
	}
}

1;
