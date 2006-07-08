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

		# This is passed back in the response context to $helper_request.
		my $name :Req($helper_request) = "test response context";
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

__END__

App: Calling Helper=HASH(0x18d82fc) via POE::Request=ARRAY(0x181d03c)
Helper (Helper=HASH(0x18d82fc)) is executing a request.
App emit: return value 'EmitValue123'
App emit: Helper=HASH(0x18d82fc) was called via POE::Request=ARRAY(0x181d03c)
App emit: hash keys: abc xyz
App emit: hash values: 123 890
App emit: array: a e i o u y
App emit: rsp name = test response context
App return: return value 'ReturnValueXyz'
App return: Helper=HASH(0x18d82fc) was called via POE::Request=ARRAY(0x181d03c)
App return: hash keys: abc xyz
App return: hash values: 123 890
App return: array: a e i o u y
App return: rsp: modified in catch_emit
