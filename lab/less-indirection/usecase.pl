#!/usr/bin/env perl

use warnings;
use strict;
use Delay;

# Callback based on coderef.

my $delay_1 = Delay->new(
	{
		interval => 1,
		on_done => \&coderef_callback,
		data => {
			name => "delay_1",
		},
	},
);

# Callback based on creator's package name.

my $delay_2 = Delay->new(
	{
		interval => 1.33,
		on_done => "package_method_callback",
		data => {
			name => "delay_2",
		},
	},
);

{
	package Whee;
	use Moose;
	extends qw(Object);

	has delay => (
		isa => 'Object',
		is => 'rw',
	);

	sub BUILD {
		my $self = shift;

		$self->delay(
			Delay->new(
				{
					interval => 1.66,
					on_done => "object_method_callback",
					data => {
						name => "delay_3",
					},
				},
			),
		);
	}

	sub object_method_callback {
		my ($object, $delay) = @_;
		warn $delay->data()->{name}, " delivered to $object at ", scalar(localtime);
		$delay->repeat();
	}
}

my $whee = Whee->new();

POE::Kernel->run();
exit;

sub coderef_callback {
	my $delay = shift;
	warn $delay->data()->{name}, " delivered to coderef at ", scalar(localtime);
	$delay->repeat();
}

sub package_method_callback {
	my ($class, $delay) = @_;
	warn $delay->data()->{name}, " delivered to $class at ", scalar(localtime);
	$delay->repeat();
}
