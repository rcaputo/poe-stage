#!/usr/bin/env perl
# $Id$

# Checking out a new handler naming convention.
#
# Currently a non-functional use case based on examples/ping-pong and
# POE::Stage::Echoer.

### Application stage.

{
	package App;

	use warnings;
	use strict;

	# use Echoer;
	use POE::Stage qw(:base);

	# The on_ prefix makes it a message handler.  This handler has no
	# role, which implies that it handles a request from a superstage.

	sub on_run {
		my $req_substage = POE::Stage::Something->new();
		my $self->send_request();
	}

	# No on_ prefix, so this method is called directly.  Handler magic
	# (persistent lexical state) is assigned with the :Handler
	# attribute.

	sub send_request :Handler {
		my $req_subrequest = POE::Request->new(
			stage => my $req_substage,
			method => "something",
			role => "make_me_a_sandwich",
			on_blort => "handle_blort",
		);
	}

	# The request above is assigned the "make_me_a_sandwich" role.  The
	# next two handlers deal with results from that role.  Their names
	# fit the pattern "on_${role}_${result_type}".

	sub on_make_me_a_sandwich_success {
		print "Got a sandwich!  Asking for another...\n";
		my $self->send_request();
	}

	sub on_make_me_a_sandwich_failure {
		print "No sandwich?  Ask for it again...\n";
		my $self->send_request();
	}

	# This handler was explicitly assigned to handle "blort" return
	# types, via "on_blort" in send_request().  It requires :Handler
	# since its name doesn't begin with "on_".

	sub handle_blort :Handler {
		print "Blort?  It doesn't even throw us blort!  Try again...\n";
		my $self->send_request();
	}

	# The more specific on_blort overrides the more general role
	# handling.  Therefore on_make_me_a_sandwich_blort() will never be
	# called.

	sub on_make_me_a_sandwich_blort {
		die "This is not happening";
	}
}

### Emulate some task that fails 10% of the time.

{
	package Something;

	use warnings;
	use strict;

	use POE::Stage qw(:base);

	sub on_something {
		my $req->return(
			type => ((rand() < 0.1) ? "failure" : "success"),
		);
	}
}

# Out in main land.  Instantiate and run the App class.

my $app = App->new();
my $initial_request = POE::Request->new(
	stage => $app,
	method => "run",
);

POE::Kernel->run();   # aww, still not abstract...
exit;
