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
our @EXPORT = qw(declare);

sub declare(@) {
	print "declare() called with:\n";
	for (my $i = 0; $i < @_; $i++) {
		my $val = $_[$i];
		$val = "(undef)" unless defined $val;
		$val = "(empty)" unless length $val;

		print "  var $i (", \$_[$i], "): ", var_name(1, \$_[$i]), " = $val\n"

		# The intended application:
		#   Remove the sigil, and hang onto it.
		#   If the variable matches /^arg_/, then do the :Arg magic.
		#   If it matches /^req_/, then do :Req magic.
		#   If it's "$" . "self", then do :Self magic.
		#   etc.
	}

}

1;
