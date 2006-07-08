#!perl
# $Id$

# Experiment to sweeten $self->{req} and $self->{rsp}.  Rather than
# use $self->{req}{foo}, I would like to declare a scalar and have it
# magically connected to $self->{req}.

use warnings;
use strict;
use base qw(SweetState);
use Time::HiRes qw(time);

# Main code here.
sub try {

	my $foo :Req = time();
	print "$foo\n";

	my %bar :Req = ( a => 1);
	$bar{b} = 2;
	print "A=$bar{a} B=$bar{b}\n";

	my @baz :Req = qw(a e i o u y);
	print "@baz\n";

	my $two :Req($foo);
}

try();
try();
