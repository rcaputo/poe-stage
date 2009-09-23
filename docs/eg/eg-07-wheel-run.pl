#!/usr/bin/perl

use warnings;
use strict;
use lib qw(../lib);

# Demonstrate how wheels may be encapsulated in thin,
# configuration-only subclasses.

{
	package Runner;
	use Moose;
	extends 'Reflex::Object';
	use Reflex::POE::Wheel::Run;

	has wheel => (
		isa => 'Reflex::POE::Wheel::Run|Undef',
		is  => 'rw',
	);

	sub BUILD {
		my $self = shift;

		$self->wheel(
			Reflex::POE::Wheel::Run->new(
				Program => "$^X -wle 'print qq[pid(\$\$) moo(\$_)] for 1..10; exit'",
				observers => [
					{
						observer => $self,
						role     => 'child',
					},
				],
			)
		);
	}

	sub on_child_stdin {
		print "stdin flushed\n";
	}

	sub on_child_stdout {
		my ($self, $args) = @_;
		print "stdout: $args->{output}\n";
	}

	sub on_child_stderr {
		my ($self, $args) = @_;
		print "stderr: $args->{output}\n";
	}

	sub on_child_error {
		my ($self, $args) = @_;
		return if $args->{operation} eq "read";
		print "$args->{operation} error $args->{errnum}: $args->{errstr}\n";
	}

	sub on_child_close {
		my ($self, $args) = @_;
		print "child closed all output\n";
	}

	sub on_child_signal {
		my ($self, $args) = @_;
		print "child $args->{pid} exited: $args->{exit}\n";
		$self->wheel(undef);
	}
}

# Main.

my $runner = Runner->new();
Reflex::Object->run_all();
exit;
