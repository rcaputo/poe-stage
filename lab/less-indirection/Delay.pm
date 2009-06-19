package Delay;

use Moose;
use Scalar::Util qw(weaken);
use Object;
extends qw(Object);

has interval => (
	isa => 'Num',
	is => 'rw',
);

has alarm_id => (
	isa => 'Str',
	is => 'rw',
);

has data => (
	isa => 'HashRef',
	is => 'rw',
);

has on_done => (
	isa => 'CodeRef|Str',
	is => 'ro',
);

has auto_repeat => (
	isa => 'Bool',
	is => 'rw',
);

sub BUILD {
	my $self = shift;
	$self->repeat();
}

sub repeat {
	my $self = shift;

	$self->alarm_id(
		$POE::Kernel::poe_kernel->call(
			$self->session_id(),
			'set_timer',
			$self->interval(),
			$self
		)
	);
}

sub _deliver {
	my $self = shift;
	$self->alarm_id(0);

	my $on_done = $self->on_done();
	if (ref $on_done) {
		return $on_done->($self);
	}

	$self->parent()->$on_done($self);

	$self->repeat() if $self->auto_repeat();
}

sub DEMOLISH {
	warn "demolish: @_";
}

1;
