# ugly, barely tested, useless (since event-loop can't accomodate
# any events other than async calls).  simple example of concept.

# perl -MPromise -le '$r = Promise->call(sub { "hello" }); \
# $r->when(sub { print "@_" }, "world"); Promise->run'

package Promise;

use strict;
use warnings;

use Resolver;

use constant STATE => 0;
use constant VALUE => 1;
use constant WHEN  => 2;
use constant CATCH => 3;

use constant UNRESOLVED => 0;
use constant RESOLVED   => WHEN;
use constant BROKEN     => CATCH;

our @_runqueue;

sub run : method {
	POE::Kernel->run();
	while (my @queue = splice @_runqueue) {
		for my $event (@queue) {
			my ($res, $sub, @args) = @$event;
			my $retval = eval { $sub->(@args) };
			$@ ? $res->die($@) : $res->done($retval)  if $res;
		}
	}
}

sub new : method {
	my ($class) = @_;
	my $p = bless [UNRESOLVED, undef], $class;
	my $r = bless \$p, 'Resolver';
	wantarray ? ($p, $r) : [ $p, $r ]
}

sub when : method {
	my $p = shift;
	my $sub = shift;
	$p->[STATE] != BROKEN  or return $p;
	my ($rp, $rr) = defined(wantarray) ? Promise->new : ();
	my $ev = sub{\@_}->($rr, $sub, $p->[VALUE], @_);
	if ($p->[STATE] == RESOLVED) {
		push @_runqueue, $ev;
	} else {
		push @{$p->[WHEN]}, $ev;
	}
	$rp
}

sub catch : method {
	my $p = shift;
	my $sub = shift;
	$p->[STATE] != RESOLVED  or return;
	my $ev = sub{\@_}->(undef, $sub, $p->[VALUE], @_);
	if ($p->[STATE] == BROKEN) {
		push @_runqueue, $ev;
	} else {
		push @{$p->[CATCH]}, $ev;
	}
}

sub call : method {
	my $p = shift;
	if (ref $p) {
		my $sub = shift;
		return $p->when(sub { shift->$sub(@_) }, @_);
	} else {
		my ($rp, $rr) = defined(wantarray) ? Promise->new : ();
		push @_runqueue, [ $rr, @_ ];
		return $rp;
	}
}

42
