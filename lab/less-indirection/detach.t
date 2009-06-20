#!/usr/bin/env perl

use warnings;
use strict;
use Test::More tests => 9;

{
	package Child;
	use Moose;
	extends qw(Object);

	has destruct_order => (
		isa => 'ArrayRef',
		is => 'rw',
	);

	sub DEMOLISH {
		my $self = shift;
		push @{$self->destruct_order()}, ref($self);
	}
}

{
	package Parent;
	use Moose;
	extends qw(Object);

	has destruct_order => (
		isa => 'ArrayRef',
		is => 'rw',
	);

	sub create_and_manage_child {
		my $self = shift;
		my $child = Child->new(destruct_order => $self->destruct_order());
		$self->manage($child);
	}

	sub spawn_a_child {
		my $self = shift;
		Child->spawn(destruct_order => $self->destruct_order());
	}

	sub create_manage_and_abandon_child {
		my $self = shift;
		my $child = Child->new(destruct_order => $self->destruct_order());
		$self->manage($child);
		push @{$self->destruct_order()}, "post-manage";
		$child = undef;
		push @{$self->destruct_order()}, "post-undef";
		$self->abandon($_) foreach $self->children();
		push @{$self->destruct_order()}, "post-abandon";
	}

	sub DEMOLISH {
		my $self = shift;
		push @{$self->destruct_order()}, ref($self);
	}
}

# Testing the create-and-manage pattern.

{
	my @destruct_order;
	my $test_subject = Parent->new(destruct_order => \@destruct_order);
	is_deeply(
		\@destruct_order,
		[],
		"creating doesn't trigger destruction"
	);

	$test_subject->create_and_manage_child();
	is_deeply(
		\@destruct_order,
		[],
		"create_and_manage_child persists the child"
	);

	$test_subject = undef;
	is_deeply(
		\@destruct_order,
		[qw(Parent Child)],
		"managed children destroy in expected order"
	);
}

# Testing the spawn pattern.

{
	my @destruct_order;
	my $test_subject = Parent->new(destruct_order => \@destruct_order);
	is_deeply(
		\@destruct_order,
		[],
		"creating doesn't trigger destruction"
	);

	$test_subject->create_and_manage_child();
	is_deeply(
		\@destruct_order,
		[],
		"spawn persists the child"
	);

	$test_subject = undef;
	is_deeply(
		\@destruct_order,
		[qw(Parent Child)],
		"managed children destroy in expected order"
	);
}

# Abandoning should reverse the destruction order.

{
	my @destruct_order;
	my $test_subject = Parent->new(destruct_order => \@destruct_order);
	is_deeply(
		\@destruct_order,
		[],
		"creating doesn't trigger destruction"
	);

	$test_subject->create_manage_and_abandon_child();
	is_deeply(
		\@destruct_order,
		[qw(post-manage post-undef Child post-abandon)],
		"spawn persists the child"
	);

	$test_subject = undef;
	is_deeply(
		\@destruct_order,
		[qw(post-manage post-undef Child post-abandon Parent)],
		"managed children destroy in expected order"
	);
}
