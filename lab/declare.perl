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

# $object->declare(...) fails because function prototypes don't work
# with methods in Perl.

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

	# Attempts at sweet object member declarations.

	{
		package Object;
		sub new { return bless [ ], shift }
	}

	my $obj = Object->new();

	members $obj => my $x, my $y;
	prefixed $obj => my $pfx_x, my $pfx_y;

	# Often I want to copy variables from one place to another.  I try
	# to do this all the time:  $req->{foo} = $arg->{foo}.
	#
	# Prefixing lets me do it this way:
	#
	#   declare my $arg_foo;
	#   init my $req_foo = $arg_foo;
	#
	# I think it's a PITA though.

#	sub handler ($&) {
#		my ($name, $sub) = @_;
#		print "handler $name => $sub\n";
#	}
#
#	handler moo => sub {
#		my $req_foo = my $arg_foo;
#		print "moo\n";
#	};

	use Devel::LexAlias qw(lexalias);
	use PadWalker qw(peek_sub);

	sub foo {
		print "foo = ", (my $ctx_foo), "\n";
		print "blag = ", (my $arg_blag), "\n";

		# my $arg_foo
		# my $req_foo
		# my $rsp_foo

		# Still need a way to provide an arbitrary prefix.
		#
		# prefix $object, my $pfx_foo, my $pfx_bar;
	}

	sub get_member_ref ($$) {
		my ($hash, $member) = @_;
		my $value = $hash->{$member};
		return $value if ref($value);
		return \$value;
	}

	sub call (&$$) {
		my ($sub, $context, $args) = @_;

		my $pad = peek_sub($sub);
		while (my ($var, $ref) = each %$pad) {
			if ($var =~ /^(.)(ctx_)(\S+)/) {
				my $member = "$1$3";
				lexalias($sub, $var, get_member_ref($context, $member));
				next;
			}
			if ($var =~ /^(.)(arg_)(\S+)/) {
				my $member = $3;
				lexalias($sub, $var, get_member_ref($args, $member));
				next;
			}
		}

		$sub->();
	}

	call \&foo, { '$foo' => 123 }, { blag => 456 };

# Not sure if this is the right way.  Commenting it out for later.

#	sub init_from ($) {
#		print "init_from($_[0])\n";
#		return $_[0];
#	}
#
#	sub ARGS () { \"args" }
#	sub args () { ARGS }
#
#	sub PFX () { \"prefixed" }
#	sub pfx () { print "pfx\n"; return PFX }
#
#	sub my_declare (\[$@%&];\[$@%&]\[$@%&]\[$@%&]\[$@%&]\[$@%&]\[$@%&]\[$@%&]\[$@%&]) {
#		print "my_declare: @_\n";
#		foreach (@_) {
#			print "  ref: $_\n";
#			if (ref() eq "REF") {
#				if ($$_ == ARGS) {
#					print "    init_from args!\n";
#				}
#				if ($$_ == PFX) {
#					print "    prefixed!\n";
#				}
#			}
#		}
#	}
#
#	my_declare init_from args, my $x1, pfx, my @x2, my %x3;
}
