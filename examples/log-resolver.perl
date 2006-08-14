#!/usr/bin/perl
# $Id$

# Resolve IP addresses in log files into their hosts, in some number
# of parallel requests.  This example exercises the system's ability
# to manage and track multiple consumer requests to a single producer.

use warnings;
use strict;

{
	package App;

	use warnings;
	use strict;

	use POE::Stage qw(:base self);
	use POE::Stage::Resolver;

	sub run {

		# Start a handful of initial requests.
		for (1..5) {
			my $next_address = read_next_address();
			last unless defined $next_address;

			self->resolve_address($next_address);
		}
	}

	sub handle_host {
		my ($input, $packet) :Arg;

		my @answers = $packet->answer();
		foreach my $answer (@answers) {
			print(
				"Resolved: $input = type(", $answer->type(), ") data(",
				$answer->rdatastr, ")\n"
			);
		}

		# Clean up the one-time Stage.
		#
		# TODO - What if this were optional?  If new() were to be called
		# in void context, the framework could hold onto the stage until
		# it it called return() or cancel().  Then the framework frees it.

		self->resolve_address(read_next_address());
	}

	# Handle some error.
	sub handle_error {
		my ($input, $error) :Args;

		print "Error: $input = $error\n";

		self->resolve_address(read_next_address());
	}

	# Plain old subroutine.  Doesn't handle events.
	sub read_next_address {
		while (<main::DATA>) {
			chomp;
			s/\s*\#.*$//;     # Discard comments.
			next if /^\s*$/;  # Discard blank lines.
			return $_;        # Return a significant line.
		}
		return;             # EOF.
	}

	# Plain old method.  Doesn't handle events.
	sub resolve_address {
		my ($self, $next_address) = @_;

		my $resolver :Req;

		unless (defined $next_address) {
			$resolver = undef;
			return;
		}

		# Create a self-requesting stage.
		$resolver = POE::Stage::Resolver->new(
			on_success  => "handle_host",
			on_error    => "handle_error",
			args        => {
				input     => $next_address,
			},
		);
	}
}

# Main program.

my $app = App->new();
my $req = POE::Request->new(
	stage    => $app,
	method   => "run",
);

POE::Kernel->run();
exit;

__DATA__
141.213.238.252
192.116.231.44
193.109.122.77
193.163.220.3
193.201.200.130
194.109.129.220
195.111.64.195
195.82.114.48
198.163.214.60
198.175.186.5
198.252.144.2
198.3.160.3
204.92.73.10
205.210.145.2
209.2.32.38
216.193.223.223
216.32.207.207
217.17.33.10
64.156.25.83
65.77.140.140
66.225.225.225
66.243.36.134
66.33.204.143
66.33.218.20
68.213.211.142
69.16.172.2
80.240.238.17
