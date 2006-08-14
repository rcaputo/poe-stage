#!perl
# $Id$

# Show how most of the attributes and exported functions work in the
# syntax implemented by revision 100.  Sample run output is after
# __END__.

use warnings;
use strict;

# Every application needs at least one POE::Stage object, and an
# initial request must be fired at it to get things rolling.

my $app = ExampleApp->new();
my $req = POE::Request->new(
	stage => $app,
	method => "run",
);

# The abstraction is not complete, however.  The base POE framework
# still peeks through cracks in the facade.  Here POE's main loop is
# started so that the program can run.  run() will return when all
# requests have ended.

POE::Kernel->run();
exit;

# The example application.  It highlights POE::Stage's syntactical
# sugar.

{
	package ExampleApp;

	# The :base export adds POE::Stage to the calling package's @ISA.
	#
	# self, req, and rsp may also be exported.  These always return the
	# current POE::Stage object, the current POE::Request being handled,
	# and the current POE::Response being received (when applicable).
	#
	# These exported functions are used strictly for method calls.  Look
	# for :Self, :Req, :Rsp, and :Arg for data members.

	use POE::Stage qw(:base self req);

	sub run {

		# The :Self attribute allows code to declare lexicals that
		# represent self() data members.  The contents of :Self members
		# are scoped to the current POE::Stage object, so they're visible
		# from any of its methods.  The code needs to re-declare the
		# variables in every code scope in which they'll be needed, as
		# you'll see in later methods.
		#
		# In this case, the equivalent of $self->{'$memb'} is declared and
		# initialized.

		my $memb :Self = "current POE::Stage member";
		warn "run: member($memb)\n";

		# The :Req attribute allows code to declare lexicals that
		# represent req() data members.  The contents of :Req members are
		# availale from any method executed within that request's context.
		#
		# In this case, a sub-request is created and stored in the current
		# request.  If the current request is canceled for any reason, the
		# chain of destruction will cascade into the sub-request.

		my $req :Req = POE::Request->new(
			stage => self,
			method => 'other',
			on_return => 'handle_return',
		);

		# A data member ($moo) is initialized within the current request.
		# It's done within a block so that this lexical won't interfere
		# with the next one we create---which has the same name.

		{
			my $moo :Req = "moo in the request";
			warn "run: req.moo($moo)\n";
		}

		# The :Req attribute can be used to declare lexicals within a
		# specific requests.  In this case, $moo is a data member of the
		# sub-request rather than of the current one.  This allows a
		# requester to tack context onto the request in such a way that
		# responses include it.  See the handle_return() use of :Rsp for
		# details on getting the data back out of a response.

		{
			my $moo :Req($req) = "in the sub-request";
			warn "run: subreq.moo($moo)\n";
		}
	}

	# Handle the "other" request.  Since the method is in the same
	# POE::Stage, it will have the value previously stored within it.
	# This method is executed as a handler for a sub-request, however,
	# so its "current" request is different from that of run()'s.

	sub other {

		# $memb is declared to be a member of the current POE::Stage.  It
		# takes on the current value of self's '$memb' member because
		# nothing is stored into it.

		my $memb :Self;
		warn "other: member($memb)\n";

		# '$moo' is declared to be a member of the current request.  Like
		# $memb above, nothing is store into it, so it takes on the
		# member's previous value.  In this case, however, the "current"
		# request is the sub-request from run().

		{
			my $moo :Req;
			warn "other: req.moo($moo)\n";
		}

		# Return a response for the current request, along with a value
		# that will be passed to the response handler as an argument.  The
		# exported req() function represents the request itself, and it's
		# used to call methods on this request.
		#
		# The request's return() method takes at least two named
		# parameters: type and args.
		#
		# The type parameter determines the return type, and is used to
		# look up the appropriate handler.  It defaults to "return", which
		# is fine for current purposes.
		#
		# The args parameter is a hashref of named arguments that will be
		# passed to the return handler.  In this case, the following
		# handle_return() method.
		#
		# And if you haven't guessed already, handle_return() is called to
		# handle type => "return" messages because the on_return parameter
		# to the original request said so.

		req->return(args => { something => "returned value" });
	}

	# Finally we handle the return value.  This example shows how to
	# accept return values and to access data stored in the context of
	# the original request.

	sub handle_return {
		# Once again, $memb is a member of the current POE::Stage object.

		my $memb :Self;
		warn "handle_return: member($memb)\n";

		# The :Arg attribute is used to refer to arguments passed into
		# this method.

		my $something :Arg;
		warn "handle_return: arg.something($something)\n";

		# The current request is the one that invoked this stage's run()
		# method.

		{
			my $moo :Req;
			warn "handle_return: req.moo($moo)\n";
		}

		# There is a response context since this method is invoked to
		# handle a response to a previous request.  In this case, :Rsp is
		# used to declare lexicals that ar members of the sub-request
		# being responded to.
		#
		# And so the magic cookie sent with the request is available to
		# the response's handler.  The circle is complete.

		{
			my $moo :Rsp;
			warn "handle_return: rsp.moo($moo)\n";
		}
	}
}

__END__

1) poerbook:~/projects/poe-stage% perl -Ilib examples/attributes.perl

run: member(current POE::Stage member)
run: req.moo(moo in the request)
run: subreq.moo(in the sub-request)
other: member(current POE::Stage member)
other: req.moo(in the sub-request)
handle_return: member(current POE::Stage member)
handle_return: arg.something(returned value)
handle_return: req.moo(moo in the request)
handle_return: rsp.moo(in the sub-request)
