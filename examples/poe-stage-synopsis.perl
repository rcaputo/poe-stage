#!/usr/bin/env perl
{
	package App;
	use POE::Stage::App qw(:base);
	sub on_run {
		print "hello, ", my $arg_whom, "!\n";
	}
}
App->run( whom => "world" );
exit;
