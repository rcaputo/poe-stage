#!/usr/bin/env perl
# $Id$

# TODO - Need a signal watcher.

use warnings;
use strict;

use lib qw(./lib ../lib);

{
	package Generic;
	use POE::Stage qw(:base);
	use POE::Pipe::OneWay;
	use POE::Watcher::Input;
	use Storable qw(nfreeze thaw);

	sub on_init :Handler {
		my $arg_class;

		# Create the pipes.

		my ($stdin_r, $stdin_w) = POE::Pipe::OneWay->new();
		die "couldn’t create stdin pipe: $!" unless defined $stdin_r;

		my ($stdout_r, $stdout_w) = POE::Pipe::OneWay->new();
		die "couldn’t create stdout pipe: $!" unless defined $stdout_r;

		my ($stderr_r, $stderr_w) = POE::Pipe::OneWay->new();
		die "couldn’t create stderr pipe: $!" unless defined $stderr_r;

		# Buffers!

		my $self_buf_stdin = my $self_buf_stdout = "";

		# Fork the process.

		my $pid = fork();
		if ($pid) {
			# parent

			close $stdin_r;
			close $stdout_w;
			close $stderr_w;

			my $self_stdout = POE::Watcher::Input->new(
				handle    => $stdout_r,
				on_input  => "handle_stdout",
			);

			my $self_stderr = POE::Watcher::Input->new(
				handle    => $stderr_r,
				on_input  => "handle_stderr",
			);

			my $self_stdin = $stdin_w;
			my $old_fh = select($stdin_w);
			$| = 1;
			select($old_fh);

			return;
		}

		# child

		# Hook up the pipes.

		open( STDIN, "<&" . fileno($stdin_r) ) or die $!;
		close $stdin_w;

		open( STDOUT, ">&" . fileno($stdout_w) ) or die $!;
		close $stdout_r;

		open( STDERR, ">&" . fileno($stderr_w) ) or die $!;
		close $stderr_w;

		my $code = qq(
			perl -wle '
				use Storable qw(nfreeze thaw);
				use $arg_class;
				my \$object = $arg_class->new();
				\$| = 1;
				while (<STDIN>) {
					chomp;
					my (\$serial, \$method, \$args) = \@{thaw(pack("H*", \$_))};
					print unpack "H*", nfreeze([\$serial, \$object->\$method(\@\$args)]);
				}
			'
		);

		$code =~ s/\s+/ /g;

		exec($code);
		die;
	}

	# Need to automate this.

	sub get :Handler {
		my ($self_stdin, $arg_args);
		my $self_serial++;

		my %self_req;
		$self_req{$self_serial} = my $req;

		# TODO - Base64 would be better.
		print $self_stdin unpack(
			"H*",
			nfreeze([ $self_serial, "get", $arg_args ])
		), "\n";
	}

	sub handle_stdout :Handler {
		my $self_buf_stdin;

		my $ret = sysread(
			my $arg_handle,
			$self_buf_stdin,
			65536,
			length($self_buf_stdin)
		);

		if ($ret == 0) {
			my $req->cancel;
			return;
		}

		while ($self_buf_stdin =~ s/^\s*(\S+)\s+//) {
			my ($serial, $result) = @{thaw(pack("H*", $1))};
			my %self_req;
			my $delivery = delete $self_req{$serial};
			$delivery->return(args => { return => $result });
		}
	}

	sub handle_stderr :Handler {
		while (sysread(my $arg_handle, my $buf = "", 65536)) {
			print $buf;
		}
	}
}

{
	package App;
	use POE::Stage::App qw(:base);

	use LWP::UserAgent;

	sub on_run :Handler {
		my $req_lwp = Generic->new(
			class => 'LWP::UserAgent',
		);

		my $req_ping = POE::Request->new(
			stage   => $req_lwp,
			method  => "get",
			args    => { args => [ "http://yahoo.com/" ] },
			role    => "ping",
		);
	}

	sub on_ping_return {
		print my $arg_return->as_string(), "\n";
		my $req_lwp = undef;
	}
}

# Main program.  Instantiate and run the App.

App->new()->run();
exit;
