# $Id$

# Sweeten @_ by eliminating any reference to it.  Use attributes
# instead.

package SweetAtUnder;

use warnings;
use strict;

use Attribute::Handlers;
use Scalar::Util qw(blessed reftype);
use Carp qw(croak);
use PadWalker qw(var_name peek_my);

sub Arg :ATTR(ANY,RAWDATA) {
	my ($pkg, $sym, $ref, $attr, $data, $phase) = @_;
	croak "can't register blessed things as Arg fields" if blessed($ref);
	croak "can only register scalars as Arg fields" if ref($ref) ne "SCALAR";

	my $name = var_name(4, $ref);
	$name =~ s/^[\$\%\@]//;

	package DB;
	my @x = caller(4);
	$$ref = $DB::args[1]{$name};
}

sub Self :ATTR(ANY,RAWDATA) {
	my $ref = $_[2];
	croak "can't register blessed things as Self fields" if blessed($ref);

	package DB;
	my @x = caller(4);
	$$ref = $DB::args[0];
}

sub Memb :ATTR(SCALAR,RAWDATA) {
	my $ref = $_[2];
	croak "can't register blessed things as Memb fields" if blessed($ref);

	my $name = var_name(4, $ref);

	package DB;
	my @x = caller(4);
	$$ref = $DB::args[0]->{$name};
}

sub Memb :ATTR(ARRAY,RAWDATA) {
	my $ref = $_[2];
	croak "can't register blessed things as Memb fields" if blessed($ref);

	my $name = var_name(4, $ref);

	package DB;
	my @x = caller(4);
	@$ref = @{$DB::args[0]->{$name}};
}

sub Memb :ATTR(HASH,RAWDATA) {
	my $ref = $_[2];
	croak "can't register blessed things as Memb fields" if blessed($ref);

	my $name = var_name(4, $ref);

	package DB;
	my @x = caller(4);
	%$ref = %{$DB::args[0]->{$name}};
}
1;
