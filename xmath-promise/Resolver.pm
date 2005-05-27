package Resolver;

use constant STATE => 0;
use constant VALUE => 1;
use constant WHEN  => 2;
use constant CATCH => 3;

use constant UNRESOLVED => 0;
use constant RESOLVED   => WHEN;
use constant BROKEN     => CATCH;

use Carp;

sub done : method {
	my ($r, $value) = @_;
	my $p = $$r;
	if ($p->[STATE] != UNRESOLVED) {
		croak "Promise is " . ("", "resolved", "broken")[$p->[STATE]];
	}
	$p->[STATE] = RESOLVED;
	$p->[VALUE] = $value;
	delete $p->[CATCH];
	push @Promise::_runqueue, @{delete $p->[WHEN]}  if $p->[WHEN];
}

sub die : method {
	my ($r, $error) = @_;
	$error = "Broken promise" if @_ < 2;
	my $p = $$r;
	if ($p->[STATE] != UNRESOLVED) {
		croak "Promise is " . ("", "resolved", "broken")[$p->[STATE]];
	}
	$p->[STATE] = BROKEN;
	$p->[VALUE] = $error;
	push @Promise::_runqueue, @{delete $p->[CATCH]}  if $p->[CATCH];
	delete $p->[WHEN];
}

42


