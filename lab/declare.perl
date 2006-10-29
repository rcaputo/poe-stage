#!perl
# $Id$

# Grrrr.  Declaring variables as attributes is terrible.  I hate it.
# You can't have lexical names overlap between different contexts.
# For example, my $something :Req = my $something :Arg.  Can't be
# done!  Have I mentioned I hate it?

# So, this is an attempt to find something better.  Define a grammar
# for declaring variables in odd scopes:
#
# declare($x, @y, %z) allows variables to be declared within
# POE::Stage's various scopes.
#
# init my $x = 1; allows declaration and initialization, but due to
# Perl's syntactic limitations they may only be scalars.

# Current sample output:
#
# 1) poerbook:~/projects/poe-stage/lab% perl declare.perl
# init() called with:
#   var 0 (SCALAR(0x180a2e4)): $a_1 = a1
#   var 1 (SCALAR(0x180a2f0)): $a_2 = a2
#   var 2 (SCALAR(0x180a338)): $a_3 = a3
#   var 3 (SCALAR(0x180a320)): $a_4 = a4
# init() called with:
#   var 0 (SCALAR(0x180a3f8)): $b_1 = (undef)
#   var 1 (SCALAR(0x180a464)): $b_2 = (undef)
# init() called with:
#   var 0 (SCALAR(0x180a488)): $c_1 = c1
#   var 1 (SCALAR(0x180a578)): $c_2 = c2
# init() called with:
#   var 0 (SCALAR(0x182c1b0)): $d_1 = d1
#   var 1 (SCALAR(0x182c1c8)): $d_2 = d2
# init() called with:
#   var 0 (SCALAR(0x182c204)): $e_1 = e1
# init() called with:
#   var 0 (SCALAR(0x182c234)): $f_1 = f1
#   var 1 (SCALAR(0x182c24c)): $f_2 = f2
#   var 2 (SCALAR(0x182c288)): $f_3 = f3
#   var 3 (SCALAR(0x182c2a0)): $f_4 = f4
# init() called with:
#   var 0 (ARRAY(0x182c300)): @g_1 = (empty)
# init() called with:
#   var 0 (ARRAY(0x182c354)): @g_2 = (empty)
# init() called with:
#   var 0 (SCALAR(0x182c360)): $scalar = (undef)
#   var 1 (ARRAY(0x182c390)): @array = (empty)
#   var 2 (HASH(0x182c3a8)): %hash = (empty)
# 

{
	use Declare;

	init(
		my($a_1, $a_2) = qw(a1 a2),
		my($a_3, $a_4) = qw(a3 a4),
	);

	declare(
		my $b_1,
		my $b_2,
	);

	init my ($c_1, $c_2) = qw(c1 c2);

	init(
		my $d_1 = "d1",
		my $d_2 = "d2",
	);

	init my $e_1 = "e1";

	init
		my ($f_1, $f_2) = qw(f1 f2),
		my ($f_3, $f_4) = qw(f3 f4);

	declare my @g_1;
	@g_1 = qw(g1a g1b g1c);

	declare my @g_2;
	declare my $scalar, my @array, my %hash;
}
