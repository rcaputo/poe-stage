# $Id$

package Stage;

use warnings;
use strict;

use POE::Kernel;
use POE::Session;
use base qw(POE::Session);

use Scalar::Util qw(blessed);
use Carp qw(croak);

sub import {
	my ($class, $signature) = @_;

	while (my ($command, $method) = each %$signature) {
		warn "$class.$command = $method\n";
	}
}

sub new {
	croak "Stage cannot be created with new().  Try using create()";
}

sub instantiate {
	my ($class, $param) = @_;

	$param->{inline_states}{__stage_timer} = sub {
		my ($kernel, $session, $timer_object, $call) = @_[
		  KERNEL, SESSION, ARG0, ARG1
		];
		$timer_object = $call->find_resource($timer_object);
		return unless $timer_object;

		$poe_kernel->call(
			$session, $timer_object->{event}, $call, @_[ARG2..$#_]
		);

		$call->unregister_resource($timer_object);
	};

	return $class->SUPER::instantiate($param);
}

sub _invoke_state {
	my $self = shift;  # So it's not passed to SUPER.
	my ($src, $state, $etc, $file, $line, $from) = @_;

	my $call = $etc->[0];
	my $isa_call = ref($call) && blessed($call) && $call->isa("Call");

	if ($isa_call) {
		$call->_activate();
		eval { $call->_receive(); };
		if (0 and $@) {
			warn $@;
			use YAML qw(Dump);
			warn Dump $call;
			die "state($state) etc(@$etc)";
		}
	}

	# XXX - We aren't tracking wantarray state here.
	$self->SUPER::_invoke_state(@_);

	if ($isa_call) {
		$call->_deactivate();
	}
}

1;

__END__

=head1 NAME

Stage - A small wrapper around POE::Session to track Call states.

=head1 SYNOPSIS

Stage is a subclass of POE::Session.  It does not alter its base
class' public interface.

=head1 DESCRIPTION

Stage is a thin wrapper for POE::Session.  It tracks the current Call
context so that return() will work properly.  The tracking should also
be useful for future features.

You just need to remember one thing: Use Stage wherever you would
normally use POE::Session when you're working with Call objects.

=head1 BUGS

Event handler contexts are not maintained.  Event handler return
values are not returned.  Don't look at me like that!  We're
experimenting with a whole new set of call and return semantics, so we
don't NEED wantarray() and to preserve return values!

Well, not this early in the experiment, anyway.  :)

=head1 FUTURE

I'd like to create a set of classes to wrap POE::Kernel APIs.  Like
Delay, Alarm, Select, and so on.  They would automagically register
themselves with the current Session AND the current Call.  In theory,
when a Call destructs after return, all its little resources would
clean themselves up without being tracked explicitly.  That's just too
cool for words if it works.

=head1 LICENSE AND AUTHOR

Call is Copyright 2005 by Rocco Caputo.  All rights are reserved.  You
may modify and distribute this code under the same terms as Perl
itself.

=cut
