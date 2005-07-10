#!/usr/bin/perl
# $Id$

# Illustrate the pattern of many one request per response, where each
# response triggers another request.  This often leads to infinite
# recursion and stacks blowing up, so it's important to be sure the
# system works right in this case.

use warnings;
use strict;

{
	# The application is itself a POE::Stage.

	package App;

	use warnings;
	use strict;

	use POE::Stage::Echoer;
	use base qw(POE::Stage);

	sub run {
		my ($self, $args) = @_;

		$self->{req}{echoer} = POE::Stage::Echoer->new();
		$self->{req}{i} = 1;

		$self->send_request();
	}

	sub got_echo {
		my ($self, $args) = @_;

		print "got echo: $args->{echo}\n";

		$self->{req}{i}++;

		# Comment out this line to run indefinitely.  Great for checking
		# for memory leaks.
#		return if $self->{req}{i} > 10;

		$self->send_request();
	}

	sub send_request {
		my $self = shift;

		$self->{req}{echo_request} = POE::Request->new(
			_stage   => $self->{req}{echoer},
			_method  => "echo",

			message  => "request " . $self->{req}{i},

			_on_echo => "got_echo",
		);
	}
}

# TODO - Perhaps a magical App->run() could encapsulate the standard
# instantiation, initial requesting, and loop execution that goes on
# here.

my $app = App->new();

my $req = POE::Request->new(
	_stage => $app,
	_method => "run",
);

POE::Kernel->run();
exit;
