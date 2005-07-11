#!/usr/bin/perl
# $Id$

# Resolve IP addresses in log files into their hosts, in some number
# of parallel requests.  This example exercises the system's ability
# to manage and track multiple consumer requests to a single producer.

use warnings;
use strict;

{
	# The application is itself a POE::Stage;

	package App;

	use warnings;
	use strict;

	use base qw(POE::Stage);
	use POE::Stage::Resolver;

	sub run {
		my ($self, $args) = @_;

		# "req" is the magic field that refers to the current request we
		# are handling.  Build a new Resolver stage, and store it for the
		# duration of the "run" request.
		$self->{req}{resolver} = POE::Stage::Resolver->new();

		# Start a handful of initial requests.
		for (1..10) {

			my $next_address = read_next_address();
			last unless defined $next_address;

			$self->resolve_address($next_address);
		}
	}

	sub handle_host {
		my ($self, $args) = @_;

		# "rsp" is the magic field that contains the current response
		# being handled.
		my $response = $self->{rsp};

		# Because $self->{rsp}'s context is the same as $request above,
		# $self->{rsp}{data} will contain the address corresponding to the
		# host we've just received.
		print "Resolved: $response->{address} = $args->{host}\n";

		my $next_address = read_next_address();
		return unless defined $next_address;

		$self->resolve_address($next_address);
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

	sub resolve_address {
		my ($self, $next_address) = @_;

		# Build a request to resolve the next address into a host.
		my $request = POE::Request->new(
			_stage    => $self->{req}{resolver},
			_method   => "resolve_to_host",
			_on_host  => "handle_host",
			_on_error => "handle_error",
			address   => $next_address,
		);

		# Save the request keyed on itself.  The request is effectively
		# cancelled if we let it DESTROY, so this keeps it alive.
		$self->{req}{$request} = $request;

		# Store some local data in the request.  This data is only
		# visible from the current stage, in the context of the current
		# request we have just made ($request), or any response to it.
		# See handle_host() just below.
		#
		# TODO - Internally this should store the data where?  Where is
		# it stored now when we say $self->{req_addres} ?
		$request->{address} = $next_address;
	}
}

# Main program.

my $app = App->new();
my $req = POE::Request->new(
	_stage    => $app,
	_method   => "run",
);

POE::Kernel->run();
exit;

__DATA__
1
2
3
4
5
6
7
8
9
10
11
12
13
14
15
16
17
18
19
20
