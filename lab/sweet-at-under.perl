#!perl
# $Id$

# Experiment to replace @_ use with attributes denoting "self",
# subroutine arguments, and data members.

use lib qw(./lib ../lib);

{
	package Moo;

	use warnings;
	use strict;
	use base qw(SweetAtUnder);

	sub new {
		my $class :Self;
		my ($init_1, $init_2) :Arg;

		warn "class($class) new( init_1 => '$init_1', init_2 => '$init_2')\n";

		return bless {
			'$member' => "($init_1) ($init_2)",
			'@member' => [ $init_1, $init_2 ],
			'%member' => { $init_1, $init_2 },
		}, $class;
	}

	sub method {
		my $self :Self;
		my ($member, %member, @member) :Memb;

		warn(
			"Invoked $self -> method()\n",
			"  has scalar member($member)\n",
			"  has array member(@member)\n",
			"  has hash member($member[0] => $member{$member[0]})\n",
		);
	}
}

my $moo = Moo->new({ init_1 => "testing 123", init_2 => "testing abc" });
$moo->method();

exit;

__END__

Sample output:

class(Moo) new( init_1 => 'testing 123', init_2 => 'testing abc')
Invoked Moo=HASH(0x18225e0) -> method()
  has member((testing 123) (testing abc))
