#!/usr/bin/perl
# $Id$

# Attempt to use POE::Watcher::Wheel to encapsulate POE::Wheel::Run.

{
	package App;
	use warnings;
	use strict;

	use lib qw(./lib ../lib);
	use POE::Stage;
	use base qw(POE::Stage);
	use POE::Watcher::Wheel::Run;
	use POE::Filter::Line;

	sub run {
		my ($self, $args) = @_;

		my $process :Req = POE::Watcher::Wheel::Run->new(
			Program         => "$^X -wle 'print qq[pid(\$\$) moo(\$_)] for 1..10; exit'",
			StdoutMethod    => "handle_stdout",
			CloseMethod     => "handle_close",
		);
	}

	sub handle_stdout {
		my ($self, $args) = @_;
		use YAML;
		warn YAML::Dump($args);
	}

	sub handle_close {
		my ($self, $args) = @_;
		warn "process closed";
		my $process :Req = undef;
	}
}

package main;
use warnings;
use strict;

my $app = App->new();
my $req = POE::Request->new(
	stage   => $app,
	method  => "run",
);

# Trap SIGINT and make it exit gracefully.  Problems in destructor
# timing will become apparent when warnings in them say "during global
# destruction."

$SIG{CHLD} = "IGNORE";
$SIG{INT} = sub { warn "sigint"; exit };

POE::Kernel->run();
exit;
