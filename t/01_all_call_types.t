#!/usr/bin/perl
# $Id$
# vim: filetype=perl

use warnings;
use strict;

use Test::More tests => 19;

my $go_req;
my $key_value;

# Examine one of each call type.

{
	package Something;
	use warnings;
	use strict;
	use POE::Stage qw(:base req rsp);
	use Test::More;

	sub do_emit {
		ok(
			ref(req) eq "POE::Request",
			"do_emit req is a POE::Request object"
		);

		ok(
			req->get_id() == $go_req->get_id(),
			"do_emit req (" .  req->get_id() .
			") should match go_req (" . $go_req->get_id() . ")"
		);

		ok(
			rsp == 0,
			"do_emit rsp is zero"
		);

		# TODO - Don't bleed the requestor's state into the requestee.

		my $key :Req;
		ok(
			!defined($key),
			"do_emit key should not be defined" . (
				defined($key)
				? " (let alone be $key)"
				: ""
			)
		);

		my $newkey :Req = my $original_newkey :Self = 8675;

		req->emit(  );
		#req->emit( type => "emit" );
	}

	sub do_return {
		ok(
			ref(req) eq "POE::Request",
			"do_return req is a POE::Request object"
		);

		ok(
			req->get_id() == $go_req->get_id(),
			"do_return req (" . req->get_id() . ") should match go_req (" .
			$go_req->get_id() . ")"
		);

		ok(
			rsp == 0,
			"do_return rsp is zero"
		);

		# TODO - Don't bleed the requestor's state into the requestee.

		my $key :Req;
		ok(
			!defined($key),
			"do_return req.key should not be defined" . (
				defined($key)
				? " (let alone be $key)"
				: ""
			)
		);

		my $newkey :Req;
		ok(
			my $original_newkey :Self == $newkey,
			"do_return original_newkey should match req.newkey"
		);

		req->return();
		#req->return( type => "return" );
	}
}

{
	package App;
	use warnings;
	use strict;
	use POE::Stage qw(:base req rsp);

	use Test::More;

	sub run {
		my $something :Req = Something->new();
		my $go :Req = POE::Request->new(
			stage     => $something,
			method    => "do_emit",
			on_emit   => "do_recall",
			on_return => "do_return",
		);

		# Save the original req for comparison later.
		my $original_req :Self = req;
		$go_req = my $original_sub :Self = $go;
		$key_value = my $original_key :Self = my $key :Req($go) = 309;
	}

	sub do_recall {
		ok(
			ref(req) eq "POE::Request",
			"emit req is a POE::Request object"
		);

		ok(
			ref(rsp) eq "POE::Request::Emit",
			"emit rsp is a POE::Request::Emit object"
		);

		my $original_req :Self;
		ok(
			req->get_id() == $original_req->get_id(),
			"emit req (" . req->get_id() . ") should match original (" .
			$original_req->get_id() . ")"
		);

		my $original_sub :Self;
		ok(
			rsp->get_id() == $original_sub->get_id(),
			"emit rsp (" . rsp->get_id() . ") should match original (" .
			($original_sub->get_id()) . ")"
		);

		my $key :Rsp;
		my $original_key :Self;
		ok(
			$key == $original_key,
			"emit rsp.key ($key) should match original ($original_key)"
		);

		rsp->recall( method => "do_return" );
	}

	sub do_return {
		ok(
			ref(req) eq "POE::Request",
			"ret req is a POE::Request object"
		);

		ok(
			ref(rsp) eq "POE::Request::Return",
			"ret rsp is a POE::Request::Return object"
		);

		my $original_req :Self;
		ok(
			req->get_id() == $original_req->get_id(),
			"ret req (" . req->get_id() . ") should match original (" .
			$original_req->get_id() . ")"
		);

		my $original_sub :Self;
		ok(
			rsp->get_id() == $original_sub->get_id(),
			"ret rsp (" . rsp->get_id() . ") " .
			"should match original sub (" . $original_sub->get_id() . ")"
		);

		my $key :Rsp;
		my $original_key :Self;
		ok(
			$key == $original_key,
			"ret key ($key) " .
			"should match original ($original_key)"
		);

		# Actually does nothing.
	}
}

my $app = App->new();
my $req = POE::Request->new(
	stage  => $app,
	method => "run",
);

POE::Kernel->run();
exit;
