#!perl
# $Id$

# Goals:
# 
# 1. Lexical aliases for the different runtime continuation-like
# structures:
# 
#   a. Members of the current request.
#
#     Att: my $member :Req;
#     New: my $req_member;
#
# 	b. Members of the current response.
#
# 	  Att: my $member :Rsp;
# 	  New: my $rsp_member;
#
# 	c. Parameters in the current parameter list.
#
# 	  Att: my $member :Arg;
# 	  New: my $arg_member;
#
# 	d. The current POE::Stage instance.
#
# 	  Att: self().
# 	  New: my $self;
#
#   e. Members of the current POE::Stage instance.
#
#     Att: my $member :Self;
#     New: my $self_member;
#
# 	f. Members of a newly created POE::Request instance.
#
# 	  Att: my $member :Req($req);
# 	  New: expose $request => my $pfx_memb_1, ...;
#
# 	g. The current request object.
#
# 	  Att: req()
# 	  New: my $req;
#
# 	h. The current response object.
#
# 	  Att: rsp();
# 	  New: my $rsp;
# 
# 2. Avoiding lexical collisions when working with the same member name
# in two or more contexts.  The current lexical scope cannot map to
# member field names is two or more objects.  For instance:
# 
# 	my $foo :Arg;
# 	my $foo :Req; # Can't be done.
# 	$foo = $foo;  # Still can't be done.
#
# Prefixed lexicals solve this:
#
#   my $req_foo = my $arg_foo;
# 
# 3. Being able to bind to request and stage data members at will.
# This would solve (f) above.
#
# Currently:
# 
# 	my $req = POE::Request->new(...);
# 	my $foo :Req($req);
#
# New:
#
#   See (f) above.
#
#   expose $request => my $pfx_member, ...;

###

# The rest of this program contains works in progress of different
# grammars and syntaxes.  It should run despite being a combination of
# different ideas.
#
# About declare() and init():
#
# declare($x, @y, %z) allows variables to be declared within
# POE::Stage's various scopes.
#
# init my $x = 1; allows declaration and initialization, but due to
# Perl's syntactic limitations they may only be scalars.

# $object->declare(...) fails because function prototypes don't work
# with methods in Perl.

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
