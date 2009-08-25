# $Id$

# Clocked RS Nand latch.
# 
# S ------a\
#           (NAND1)-+
#       +-b/        |
#       |           +-S\        /-- Q
# Clk --+               (NandRS)    _
#       |           +-R/        \-- Q
#       +-a\        |
# _         (NAND2)-+
# R ------b/

package Ttl::Latch::ClockedNandRS;
use Moose;
extends 'Stage';
use Ttl::Nand;
use Ttl::Latch::NandRS;
use ObserverTrait;
use EmitterTrait;

has nand_not_r => (
	isa     => 'Ttl::Nand',
	is      => 'rw',
	traits  => ['Observer'],
	handles => { not_r => 'b' },
);

has nand_s => (
	isa     => 'Ttl::Nand',
	is      => 'rw',
	traits  => ['Observer'],
	handles => { s => 'a' },
);

has clk => (
	isa     => 'Bool',
	is      => 'rw',
	traits  => ['Emitter'],
);

sub on_my_clk {
	my ($self, $args) = @_;
	$self->nand_s()->b($args->{value});
	$self->nand_not_r()->a($args->{value});
}

has latch => (
	isa     => 'Ttl::Latch::NandRS',
	is      => 'rw',
	traits  => ['Observer'],
);

sub BUILD {
	my $self = shift;
	$self->nand_not_r( Ttl::Nand->new() );
	$self->nand_s( Ttl::Nand->new() );
	$self->latch( Ttl::Latch::NandRS->new() );
}

sub on_nand_s_out {
	my ($self, $args) = @_;
	$self->latch()->s($args->{value});
}

sub on_nand_not_r_out {
	my ($self, $args) = @_;
	$self->latch()->r($args->{value});
}

has q => (
	isa     => 'Bool',
	is      => 'rw',
	traits  => ['Emitter'],
);

has not_q => (
	isa     => 'Bool',
	is      => 'rw',
	traits  => ['Emitter'],
);

sub on_latch_q {
	my ($self, $args) = @_;
	$self->q($args->{value});
}

sub on_latch_not_q {
	my ($self, $args) = @_;
	$self->not_q($args->{value});
}

1;
