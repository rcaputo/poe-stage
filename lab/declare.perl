#!perl
# $Id$

# Grrrr.  Declaring variables as attributes is terrible.  I hate it.
# You can't have lexical names overlap between different contexts.
# For example, my $something :Req = my $something :Arg.  Can't be
# done!  Have I mentioned I hate it?
#
# So, this is an attempt to find something better.  Define a "declare"
# syntax that can grab the variable names and do things based on their
# prefix.  The practical (I hope) use case would be:
#
#   declare(
#     my $arg_something,
#     my $req_something,
#   );
#
#   $req_something = $arg_something;
#
# As you'll see after __END__, this is technically possible.

{
	use Declare;

	declare(
		my($a_1, $a_2) = qw(a1 a2),
		my($a_3, $a_4) = qw(a3 a4),
	);

	declare(
		my $b_1,
		my $b_2,
	);

	declare my ($c_1, $c_2) = qw(c1 c2);

	declare(
		my $d_1 = "d1",
		my $d_2 = "d2",
	);

	declare my $e_1 = "e1";

	declare
		my ($f_1, $f_2) = qw(f1 f2),
		my ($f_3, $f_4) = qw(f3 f4);

	# CAVEAT: Only scalars may be declared.  I'm not sure how to declare
	# arrays since the members of declare()'s @_ are aliases to the
	# values in the array, not the variable being declared.  var_name()
	# therefore can't find the variable name.  This is therefore
	# impossible at the moment.  See the bad output at the end.

	declare my @g_1 = qw(g1a g1b g1c);
}

__END__

1) poerbook:~/projects/poe-stage/lab% perl declare.perl     
declare() called with:
  var 0 (SCALAR(0x180a2e4)): $a_1 = a1
  var 1 (SCALAR(0x180a2f0)): $a_2 = a2
  var 2 (SCALAR(0x180a338)): $a_3 = a3
  var 3 (SCALAR(0x180a320)): $a_4 = a4
declare() called with:
  var 0 (SCALAR(0x180a410)): $b_1 = (undef)
  var 1 (SCALAR(0x180a44c)): $b_2 = (undef)
declare() called with:
  var 0 (SCALAR(0x180a470)): $c_1 = c1
  var 1 (SCALAR(0x180a488)): $c_2 = c2
declare() called with:
  var 0 (SCALAR(0x1820890)): $d_1 = d1
  var 1 (SCALAR(0x18208a8)): $d_2 = d2
declare() called with:
  var 0 (SCALAR(0x18208e4)): $e_1 = e1
declare() called with:
  var 0 (SCALAR(0x1820914)): $f_1 = f1
  var 1 (SCALAR(0x182092c)): $f_2 = f2
  var 2 (SCALAR(0x1820968)): $f_3 = f3
  var 3 (SCALAR(0x1820980)): $f_4 = f4
declare() called with:
  var 0 (SCALAR(0x1801380)):  = g1a
  var 1 (SCALAR(0x1801434)):  = g1b
  var 2 (SCALAR(0x1801524)):  = g1c
