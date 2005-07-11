#!/usr/bin/perl
# $Id$

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
	use base qw(POE::Stage);
	use Test::More;

	sub do_emit {
		my ($self, $args) = @_;
		diag "Something.do_emit";

		ok(
			ref($self->{req}) eq "POE::Request",
			"do_emit req is a POE::Request object"
		);

		ok(
			$self->{req} == $go_req,
			"do_emit req ($self->{req}) should match go_req ($go_req)"
		);

		ok(
			$self->{rsp} == 0,
			"do_emit rsp is zero"
		);

		# TODO - Don't bleed the requestor's state into the requestee.

		ok(
			!exists($self->{req}{key}),
			"do_emit key should not exist" . (
				exists($self->{req}{key})
				? " (let alone be $self->{req}{key})"
				: ""
			)
		);

		$self->{original_newkey} = $self->{req}{newkey} = 8675;

		$self->{req}->emit( _type => "emit" );
	}

	sub do_return {
		my ($self, $args) = @_;
		diag "Something.do_return";

		ok(
			ref($self->{req}) eq "POE::Request",
			"do_return req is a POE::Request object"
		);

		ok(
			$self->{req} == $go_req,
			"do_return req ($self->{req}) should match go_req ($go_req)"
		);

		ok(
			$self->{rsp} == 0,
			"do_return rsp is zero"
		);

		# TODO - Don't bleed the requestor's state into the requestee.

		ok(
			!exists($self->{req}{key}),
			"do_return req.key should not exist" . (
				exists($self->{req}{key})
				? " (let alone be $self->{req}{key})"
				: ""
			)
		);

		ok(
			$self->{original_newkey} == $self->{req}{newkey},
			"do_return original_newkey should match req.newkey"
		);

		$self->{req}->return( _type => "return" );
	}
}

{
	package App;
	use warnings;
	use strict;
	use base qw(POE::Stage);

	use Test::More;

	sub run {
		my ($self, $args) = @_;
		diag("App.run");
		$self->{req}{something} = Something->new();
		$self->{req}{go} = POE::Request->new(
			_stage     => $self->{req}{something},
			_method    => "do_emit",
			_on_emit   => "do_recall",
			_on_return => "do_return",
		);

		# Save the original req for comparison later.
		$self->{original_req} = $self->{req};
		$go_req = $self->{original_sub} = $self->{req}{go};

		$key_value = $self->{original_key} = $self->{req}{go}{key} = 309;
	}

	sub do_recall {
		my ($self, $args) = @_;
		diag("App.do_recall");

		ok(
			ref($self->{req}) eq "POE::Request",
			"emit req is a POE::Request object"
		);

		ok(
			ref($self->{rsp}) eq "POE::Request::Emit",
			"emit rsp is a POE::Request::Emit object"
		);

		ok(
			$self->{req} == $self->{original_req},
			"emit req ($self->{req}) should match original ($self->{original_req})"
		);

		ok(
			$self->{rsp} == $self->{original_sub},
			"emit rsp ($self->{rsp}) should match original ($self->{original_sub})"
		);

		ok(
			$self->{rsp}{key} == $self->{original_key},
			"emit rsp.key ($self->{rsp}{key}) " .
			"should match original ($self->{original_key})"
		);

		$self->{rsp}->recall( _method => "do_return" );
	}

	sub do_return {
		my ($self, $args) = @_;
		diag("App.do_return");

		ok(
			ref($self->{req}) eq "POE::Request",
			"ret req is a POE::Request object"
		);

		ok(
			ref($self->{rsp}) eq "POE::Request::Return",
			"ret rsp is a POE::Request::Return object"
		);

		ok(
			$self->{req} == $self->{original_req},
			"ret req ($self->{req}) should match original ($self->{original_req})"
		);

		ok(
			$self->{rsp} == $self->{original_sub},
			"ret rsp ($self->{rsp}) " .
			"should match original sub ($self->{original_sub})"
		);

		ok(
			$self->{rsp}{key} == $self->{original_key},
			"ret key ($self->{rsp}{key}) " .
			"should match original ($self->{original_key})"
		);

		# Actually does nothing.
	}
}

my $app = App->new();
my $req = POE::Request->new(
	_stage  => $app,
	_method => "run",
);

POE::Kernel->run();
exit;
