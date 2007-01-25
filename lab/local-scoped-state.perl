#!/usr/bin/perl
# $Id$

# Jonathan Steinert tests Philip Gwyn's hypothesis that local() may be
# used instead of push/pop for managing the current request/stage
# state.
#
# It appears that local() values only affect the package where they're
# localized.  Exported versions of the variable don't see the change.

use lib qw(./lib ../lib);

{
	package Library;
	use warnings;
	use strict;

	our $stage = '(initial)';

	# Simulate Exporter.
	sub import {
		my $package = (caller)[0];
		no strict 'refs';
		*{$package . "::stage"} = \$stage;
	}

	use Exporter;
	our @EXPORT = qw($stage);

	sub invoke {
		my ($class, $method, $temp_stage) = @_;
		local $stage = $temp_stage;

		main->$method($stage);
	}
}

package main;

use warnings;
use strict;

# BEGIN so it happens at compile time.
BEGIN { Library->import(); }

sub method {
	my ($class, $param) = @_;
	print "  method: main::stage  = $stage\n";
	print "  method: param = $param\n";
	print "  method: Library::stage = $Library::stage\n";
}

print "main: main::stage before: $stage\n";
Library->invoke("method", "my stage here");
print "main: main::stage after: $stage\n";
