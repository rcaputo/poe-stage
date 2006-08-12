#!/usr/bin/perl
# $Id$

# Test out the syntax for a TCP listener stage.

use warnings;
use strict;
use lib qw(./lib ../lib);

{
	package POE::Stage::Listener;

	use warnings;
	use strict;

	use POE::Stage;
	use base qw(POE::Stage);

	use IO::Socket::INET;
	use POE::Watcher::Input;

	# Fire off an automatic request using the stage's constructor
	# parameters.  Check the parameters while were here since this is
	# happening during new().
	#
	# TODO - Fix up error reporting so croak() reports where new() was
	# called.
	#
	# TODO - I'm not sure whether things should be stored in $self,
	# $self->{req} or what.  Very confusing.  Users will also have this
	# problem.  Hell, if *I* can't figure it out, then it sucks.

	sub init {
		my $self :Self;
		my $args = $_[1];
		my $init_request :Memb;
		my ($socket, $listen_queue) :Arg;

		# TODO - This idiom happens enough that we should abstract it.
		my $passthrough_args = delete($args->{args}) || { };

		# TODO - Common pattern: Hoist parameters out of $args and place
		# them into a request's args.  It's a butt-ugly, repetitive thing
		# to do.  Find a better way.

		die "POE::Stage::Listener requires a socket" unless $socket;

		$listen_queue ||= SOMAXCONN;

		$init_request = POE::Request->new(
			stage   => $self,
			method  => "listen",
			%$args,
			args    => {
				%$passthrough_args,
				socket => $socket,
				listen_queue => $listen_queue,
			},
		);

		# Do object-scoped initialization here.
		# TODO
	}

	# Set up the listener.

	sub listen {
		my ($socket, $listen_queue) :Arg;

		my $req_socket :Req = $socket;
		my $req_listen_queue = $listen_queue;

		# TODO - Pass in parameters for listen.  Whee.
		listen($socket, $listen_queue) or die "listen: $!";

		my $input_watcher :Req = POE::Watcher::Input->new(
			handle    => $socket,
			on_input  => "accept_connection",
		);
	}

	# Ready to accept from the socket.  Do it.

	sub accept_connection {
		my $self :Self;

		my $new_socket = (my $req_socket :Req)->accept();
		warn "accept error $!" unless $new_socket;
		$self->{req}->emit( type => "accept", socket => $new_socket );
	}
}

###

{
	package POE::Stage::EchoSession;

	use warnings;
	use strict;

	use base qw(POE::Stage);

	sub init {
		my $args = $_[1];
		my $self :Self;
		my $init_request :Memb;
		my $socket :Arg;

		my $passthrough_args = delete($args->{args}) || { };

		$init_request = POE::Request->new(
			stage => $self,
			method => "interact",
			%$args,
			args => {
				socket => $socket,
			}
		);
	}

	sub interact {
		my $socket :Arg;

		use Data::Dumper;
		warn Dumper($_[1]);

		my $input_watcher :Req = POE::Watcher::Input->new(
			handle    => $socket,
			on_input  => "process_input",
		);
	}

	sub process_input {
		my $socket :Arg;

		my $ret = sysread($socket, my $buf = "", 65536);

		use POSIX qw(EAGAIN EWOULDBLOCK);

		unless ($ret) {
			return if $! == EAGAIN or $! == EWOULDBLOCK;
			warn "read error: $!";
			my $input_watcher :Req = undef;
			return;
		}

		my ($offset, $rest) = (0, $ret);
		while ($ret) {
			my $wrote = syswrite($socket, $buf, $ret, $offset);

			# Nasty busy loop for rapid prototyping.
			unless ($wrote) {
				next if $! == EAGAIN or $! == EWOULDBLOCK;
				warn "write error: $!";
				my $input_watcher :Req = undef;
				return;
			}

			$rest -= $wrote;
			$offset += $wrote;
		}
	}

}

###

{
	package POE::Stage::EchoServer;

	use warnings;
	use strict;

	use Scalar::Util qw(weaken);
	use base qw(POE::Stage::Listener);

	sub on_my_accept {
		my $socket :Arg;

		# Do we need to save this reference?  Self-requesting stages
		# should do something magical here.
		my %sockets :Req;
		$sockets{$socket} = POE::Stage::EchoSession->new(
			socket => $socket,
		);
		weaken $sockets{$socket};
	}
}

my $app = POE::Stage::EchoServer->new(
	socket => IO::Socket::INET->new(
		LocalAddr => "127.0.0.1",
		LocalPort => 31415,
		ReuseAddr => "yes",
	),
);

sub moo {
}

POE::Kernel->run();
exit;

__END__

Do we even need an App class for self-contained subclass
components?  Nifty!  Try to avoid it.

# Creating the server object will also set it up.
# init() fires the event, self-firing style.
# We need callbacks that redirect to other stages.

my $x = POE::Stage::EchoServer->new(
	BindPort => 8675,
);

POE::Kernel->run();

Uppercase parameters are constructor arguments?  Does it matter which
are for the constructor?

Socket

on_accept
on_accept_failure
on_failure

