#!/usr/bin/perl
# $Id$

# A test program for generating mutators.

use warnings;
use strict;

{
	package Thingy;

	use Carp qw(croak);

	sub new {
		my $class = shift;
		my $self = bless { }, $class;
		$self->_init(@_);
		return $self;
	}

	sub members {
		my ($self, %members) = @_;
		my $package = ref($self);
		while (my ($member, $ignored) = each(%members)) {
			croak "Member $member already exists" if $self->can($member);
			no strict 'refs';
			*{$package . "::" . $member} = sub {
				my $self = shift;
				return $self->{$member} unless @_;
				return $self->{$member} = shift if @_ == 1;
				croak "Too many arguments to $member accessor";
			};
		}
	}
}

package main;

use base qw(Thingy);

sub _init {
	my $self = shift;

	$self->members(
		moo => 1,
		bar => 1,
		baz => 1,
	);
}

my $ob = main->new();

print $ob->moo(12, 34);
print $ob->moo;
