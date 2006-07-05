#!perl
# $Id$

# Simple call and return in POE::Stage.

use warnings;
use strict;
use POE::Stage;

# Define a simple class that does something and returns a value.

{
	package Helper;

	use warnings;
	use strict;
	use base qw(POE::Stage);

	sub do_something {
		my ($self, $args) = @_;
		print "Helper ($self) is executing a request.\n";
		$self->{req}->emit(args => { value => "EmitValue123" });
		$self->{req}->return(args => { value => "ReturnValueXyz" });
	}
}

# Define an application class to use the helper.

{
	package App;

	use warnings;
	use strict;
	use base qw(POE::Stage);

	sub call_helper {
		my $self = shift;

		my $helper :Req = Helper->new();
		my $helper_request :Req = POE::Request->new(
			stage     => $helper,
			method    => "do_something",
			on_return => "catch_return",
			on_emit   => "catch_emit",
		);

		my (%hash, @array) :Req;
		%hash = ( abc => 123, xyz => 890 );
		@array = qw( a e i o u y );

		print "App: Calling $helper via $helper_request\n";

		# TODO - This is not entirely elegant.  I'd like to have some :Rsp
		# syntax here.
		$helper_request->{'$name'} = "test response context";
	}

	sub catch_return {
		my ($self, $args) = @_;
		my ($helper, $helper_request, %hash, @array) :Req;
		my $name :Rsp;
		print(
			"App return: return value '$args->{value}'\n",
			"App return: $helper was called via $helper_request\n",
			"App return: hash keys: ", join(" ", keys %hash), "\n",
			"App return: hash values: ", join(" ", values %hash), "\n",
			"App return: array: @array\n",
			"App return: rsp: $name\n",
		);
	}

	sub catch_emit {
		my ($self, $args) = @_;
		my ($helper, $helper_request, %hash, @array) :Req;
		my $name :Rsp;
		print(
			"App emit: return value '$args->{value}'\n",
			"App emit: $helper was called via $helper_request\n",
			"App emit: hash keys: ", join(" ", keys %hash), "\n",
			"App emit: hash values: ", join(" ", values %hash), "\n",
			"App emit: array: @array\n",
			"App emit: rsp name = $name\n",
		);

		$name = "modified in catch_emit";
	}
}

# Create and start the application.

my $app = App->new();
my $req = POE::Request->new(
	stage => $app,
	method  => "call_helper",
);

# TODO - Abstract this.

POE::Kernel->run();
exit;
