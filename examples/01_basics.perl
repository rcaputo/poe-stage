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
		$self->{req}->return(args => { value => "thanks" });
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
			on_return => "catch_value",
		);

		my (%hash, @array) :Req;
		%hash = ( abc => 123, xyz => 890 );
		@array = qw( a e i o u y );

		print "App: Calling $helper via $helper_request\n";
	}

	sub catch_value {
		my ($self, $args) = @_;
		my ($helper, $helper_request, %hash, @array) :Req;
		print(
			"App: Caught return value '$args->{value}'\n",
			"App: $helper was called via $helper_request\n",
			"App: hash keys: ", join(" ", keys %hash), "\n",
			"App: hash values: ", join(" ", values %hash), "\n",
			"App: array: @array\n",
		);
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
