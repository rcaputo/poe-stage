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
		my ($self, $args) = @_;

		my $passthrough_args = delete($args->{args}) || { };

		# TODO - Common pattern: Hoist parameters out of $args and place
		# them into a request's args.  It's a butt-ugly, repetitive thing
		# to do.  Find a better way.

		my $socket = delete $args->{socket};
		die "POE::Stage::Listener requires a socket" unless $socket;

		my $listen_queue = delete($args->{listen_queue}) || SOMAXCONN;

		$self->{init_request} = POE::Request->new(
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
		my ($self, $args) = @_;

		my $socket        = $self->{req}{socket} = $args->{socket};
		my $listen_queue  = $args->{listen_queue};

		# TODO - Pass in parameters for listen.  Whee.
		listen($socket, $listen_queue) or die "listen: $!";

		$self->{req}{input_watcher} = POE::Watcher::Input->new(
			handle    => $socket,
			on_input  => "accept_connection",
		);
	}

	# Ready to accept from the socket.  Do it.

	sub accept_connection {
		my ($self, $args) = @_;

		my $new_socket = $self->{req}{socket}->accept();
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
		my ($self, $args) = @_;

		my $passthrough_args = delete($args->{args}) || { };
		my $socket = delete $args->{socket};

		$self->{init_request} = POE::Request->new(
			stage => $self,
			method => "interact",
			%$args,
			args => {
				socket => $socket,
			}
		);
	}

	sub interact {
		my ($self, $args) = @_;

		use Data::Dumper;
		warn Dumper($args);

		$self->{req}{input_watcher} = POE::Watcher::Input->new(
			handle    => $args->{socket},
			on_input  => "process_input",
		);
	}

	sub process_input {
		my ($self, $args)= @_;
		my $socket = $args->{socket};

		my $ret = sysread($socket, my $buf = "", 65536);

		use POSIX qw(EAGAIN EWOULDBLOCK);

		unless ($ret) {
			return if $! == EAGAIN or $! == EWOULDBLOCK;
			warn "read error: $!";
			delete $self->{req}{input_watcher};
			return;
		}

		my ($offset, $rest) = (0, $ret);
		while ($ret) {
			my $wrote = syswrite($socket, $buf, $ret, $offset);

			# Nasty busy loop for rapid prototyping.
			unless ($wrote) {
				next if $! == EAGAIN or $! == EWOULDBLOCK;
				warn "write error: $!";
				delete $self->{req}{input_watcher};
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
		my ($self, $args) = @_;

		my $socket = $args->{socket};

		# Do we need to save this reference?  Self-requesting stages
		# should do something magical here.
		$self->{req}{$socket} = POE::Stage::EchoSession->new(
			socket => $socket,
		);
		weaken $self->{req}{$socket};
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
