#!/usr/bin/env perl

{
	package App;
	use POE::Stage::App qw(:base);

	sub on_run {
		print "hello, ", my $arg_whom, "!\n";
	}
}

exit App->new()->run( whom => "world" );

__END__

=head1 DESCRIPTION

This example creates a simple "hello, world!" application.  It
implements a small application that greets programs by name.

=head2 Main Code

The main code is a one-liner that instantiates an App object, runs it,
and exits.

=head2 POE::Stage::App

=head3 Purpose

POE::Stage::App is a small class that implements common code for
applications.  It lives mainly to provide a simple-to-use run()
method.

Applications can use the more verbose equivalent.  For example:

	my $app = App->new();
	my $req = POE::Request->new(
		stage => $app,
		method => "on_run",
		args => { whom => "world" },
	);
	POE::Kernel->run();
	exit;

This instantiates an App object, sends it a request, then runs POE's
main loop so the request may be dispatched.  POE's main loop finally
returns when all requests (and their side effects) have completed.
The program then exits.

The verbose startup code is often a waste of effort, but it can be
useful.  See L</Alternative Startup Code>.

=head3 :base Export Directive

POE::Stage's ":base" export combines C<use> with C<use base>.  The
base class is loaded, and then the current class inherits it.  This
works for subclasses such as POE::Stage::App, as long as they don't
override import().

The more verbose classic form also works:

	use POE::Stage::App;
	use base qw(POE::Stage::App);

=head2 App

App's on_run() method is triggered by POE::Stage::App's run().
on_run() greets the world named in the "whom" parameter.

=head3 Lexical Magic: Method Arguments

POE::Stage performs some magic on lexical variables.  Among other
things, lexical variables beginning with "$arg_" are filled from the
named parameters passed with the request.

Named parameters may also be found in a traditional hashref in the
second method parameter.  This more common calling convention also
works:

	sub on_run {
		my ($self, $args) = @_;
		print "hello, $args->{whom}!\n";
	}

The lexical magic is implicit for methods with names beginning with
"on_".  All other methods work normally.  Here's a plain accessor:

	sub accessor {
		my $arg_whom; # undefined
	}

Lexical magic may be explicitly turned on by applying the :Handler
method attribute:

	sub another_accessor :Handler {
		my $arg_whom; # magical
	}

=head2 Alternative Startup Code

POE::Stage::App's run() is just one way to start programs.  Here are
two other potentially useful ways:

=head3 One Program, Many Apps

Many App instances may be started and run concurrently:

	my @apps;
	foreach my $world (qw(mercury venus earth)) {
		my $app = App->new();
		my $req = POE::Request->new(
			stage => $app,
			method => "on_run",
			args => { whom => $world },
		);
		push @apps, { app => $app, request => $req };
	}
	POE::Kernel->run();
	exit;

=head3 One App, Many Requests

A single App instance may be called upon to handle more than one
request:

	my $app = App->new();
	my @requests;
	foreach my $world (qw(mars jupiter saturn)) {
		push @requests, POE::Request->new(
			stage => $app,
			method => "on_run",
			args => { whom => $world },
		);
	}
	POE::Kernel->run();
	exit;

=head3 Caveats

The main code runs outside of a POE::Stage instance, so it cannot
handle responses from the application.  If the App code generates
useful responses, it should probably be refactored into another Stage,
then called from the main App instance.  The App can then process the
responses before exiting.

=head1 CODING STYLE

Each package lives in its own block.  This helps contain them so they
may be extracted into their own files later.

=head1 AUTHOR & LICENSE

Copyright 2008, Rocco Caputo.  CPAN ID: RCAPUTO.

Same terms as Perl itself.

Thank you.

=cut
