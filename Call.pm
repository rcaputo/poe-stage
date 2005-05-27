# $Id$

package Call;

use warnings;
use strict;

use POE::Kernel;

use Carp qw(croak carp);
use Scalar::Util qw(weaken);

sub STATE_UNSENT    () { 0x01 }
sub STATE_SENT      () { 0x02 }
sub STATE_RECEIVED  () { 0x04 }
sub STATE_RETURNING () { 0x08 }
sub STATE_RETURNED  () { 0x10 }
sub STATE_CANCELED  () { 0x20 }
sub STATE_DESTROYED () { 0x40 }

sub new {
	my ($class, %args) = @_;

	foreach my $param (qw(session event)) {
		next if exists $args{$param};
		croak "$class is missing the '$param' parameter";
	}

	my $parent = Call->_get_current_call();

	my $self = bless {
		src_session => $poe_kernel->get_active_session(),
		dst_session => delete $args{session},
		dst_event   => delete $args{event},
		args        => \%args,
		state       => STATE_UNSENT,
		returns     => { },
		parent_call => Call->_get_current_call(),
		child_calls => { },
		resources   => { },
	}, $class;

	# The pointers to children must be weak so the child calls can
	# DESTROY at appropriate times.
	if ($parent) {
		$parent->{child_calls}{$self} = $self;
		weaken $parent->{child_calls}{$self};
	}

	return $self;
}

sub on {
	my ($self, %args) = @_;

	unless ($self->{state} & STATE_UNSENT) {
		croak "can't call on() once a Call has been sent";
	}

	foreach my $param (qw(type event)) {
		next if exists $args{$param};
		croak "$self is missing the '$param' parameter";
	}

	my $type  = delete $args{type};
	my $event = delete $args{event};

	my $current_session_id = $poe_kernel->get_active_session()->ID();

	push @{$self->{returns}{$type}}, [$current_session_id, $event];
}

# TODO - Send a standard canceled message?
sub cancel {
	my $self = shift;

	if ($self->{state} & STATE_CANCELED) {
		carp "ignored cancel() on an already canceled Call";
		return;
	}

	if ($self->{state} & STATE_RETURNING) {
		carp "ignored cancel() on a returning Call";
		return;
	}

	if ($self->{state} & STATE_RETURNED) {
		carp "ignored cancel() on a returned Call";
		return;
	}

	if ($self->{state} & STATE_DESTROYED) {
		croak "can't cancel() a destroyed Call";
	}

	# Propagate cancels depth-first.  The block eval is to avoid
	# problems canceling dead children due to weakened references.
	foreach my $child (values %{$self->{child_calls}}) {
		eval { $child->cancel() };
	}

	$self->{state} = STATE_CANCELED;

	# XXX - I'm not sure about the timing of _stop_returns() vs.
	# propagating cancels.
	$self->_stop_returns();
}

sub _stop_returns {
	my $self = shift;

	while (my ($type, $returns) = each %{$self->{returns}}) {
		foreach my $return (@$returns) {
			my ($sid, $event) = @$return;
			$poe_kernel->refcount_decrement($sid, "call");
		}
	}

	# Prevent duplicate cleanup.
	$self->{returns} = { };
}

sub _start_returns {
	my $self = shift;

	while (my ($type, $returns) = each %{$self->{returns}}) {
		foreach my $return (@$returns) {
			my ($sid, $event) = @$return;
			$poe_kernel->refcount_increment($sid, "call");
		}
	}
}

sub call {
	my $self = shift;

	unless ($self->{state} & STATE_UNSENT) {
		croak "a Call must be unsent to call() it";
	}

	$poe_kernel->post(
		$self->{dst_session}, $self->{dst_event},
		$self, $self->{args}
	);

	$self->_start_returns();
	$self->{state} = STATE_SENT;
}

sub return {
	my ($self, %args) = @_;

	unless (exists $args{type}) {
		croak "return() requires a 'type'";
	}

	unless ($self->{state} & STATE_RECEIVED) {
		if ($self->{state} & STATE_RETURNING) {
			croak "can't call return() twice on a single Call";
		}
		if ($self->{state} & STATE_CANCELED) {
			croak "can't call return() on a canceled Call";
		}
		if ($self->{state} & STATE_DESTROYED) {
			croak "can't call return() on a destroyed Call";
		}
		croak "can't call return() until a Call has been received";
	}

	$self->{state} = STATE_RETURNING;
	$self->_bubble(%args);
	$self->_stop_returns();
}

sub emit {
	my ($self, %args) = @_;

	unless (exists $args{type}) {
		croak "$self requires a 'type'";
	}

	unless ($self->{state} & STATE_RECEIVED) {
		if ($self->{state} & STATE_CANCELED) {
			croak "can't call emit() on a canceled Call";
		}
		if ($self->{state} & STATE_DESTROYED) {
			croak "can't call emit() on a destroyed Call";
		}
		croak "can't call emit() until a Call has been received";
	}

	$self->_bubble(%args);
}

sub _receive {
	my $self = shift;

	unless ($self->{state} & STATE_SENT) {
		croak "can't receive() a Call that is not in transit";
	}

	$self->{state} = STATE_RECEIVED;
}

sub arg {
	my ($self, $arg) = @_;
	return $self->{args}{$arg};
}

# TODO - Need a Call chain and event/exception bubbling upwards.
# TODO - Make sure called-back session runs in its previous context.

sub _bubble {
	my ($self, %args) = @_;

	my $type = $args{type} || die;
	return unless exists $self->{returns}{$type};

	my $parent = $self->{parent_call};

	foreach my $return (@{$self->{returns}{$type}}) {
		my ($sid, $event) = @$return;

		my $c = Call->new(
			session => $sid,
			event   => $event,
			%args,
		);

#		my $call = $c;
#		my $indent = 0;
#		while ($call) {
#			my $parent = $call->{parent_call};
#			warn( ("  " x $indent++), "$call has parent $parent\n" );
#			$call = $parent;
#		}

		$c->call();
	}
}

sub _detach_from_parent {
	my $self = shift;
	if ($self->{parent_call}) {
		delete $self->{parent_call}{child_calls}{$self};
		$self->{parent_call} = undef;
	}
}

sub DESTROY {
	my $self = shift;
	$self->{state} = STATE_DESTROYED;
	$self->_detach_from_parent();
	$self->_stop_returns();
}

my @call_stack;

sub _activate {
	my $self = shift;
	push @call_stack, $self;
}

sub _deactivate {
	my $self = shift;

	if (@call_stack and $call_stack[-1] == $self) {
		pop @call_stack;
		return;
	}

	die "popping some strange call off the stack";
}

sub _get_current_call {
	my $i = @call_stack;
	while ($i--) {
		if (
			$call_stack[$i]->{state} &
			(STATE_RETURNING | STATE_RETURNED | STATE_CANCELED | STATE_DESTROYED)
		) {
			next;
		}
		return $call_stack[$i];
	}

	# 0 is false (great stopping point in a chain), but it doesn't do
	# strange things when used as a hash value (namely trigger "Odd
	# number of elements" warnings).
	return 0;
}

# Manage resources.

sub register_resource {
	my ($self, $resource) = @_;
	$self->{resources}{$resource} = $resource;
}

sub unregister_resource {
	my ($self, $resource) = @_;
	delete $self->{resources}{$resource};
}

sub find_resource {
	my ($self, $resource) = @_;
	return $self->{resources}{$resource};
}

1;

__END__

=head1 NAME

Call - A class to track inter-session call states.

=head1 SYNOPSIS

Please forgive me.  This is not a complete, executable program.  Try
one of the samples that come with this snapshot.

	# Create a call.

	my $c = Call->new(
		session => DESTINATION_SESSION,
		event   => DESTINATION_EVENT_NAME,
		EVENT_PARAMETERS_IN_KEY_VALUE_PAIRS,
	);

	# Watch for a type of result.  Only valid before a call is sent to
	# its destination.  A single Call can have multiple watchers.

	$c->on(
		RESULT_TYPE => MY_EVENT_NAME,
	);

	# Cancel a call.  UNTESTED.

	$c->cancel();

	# Send the built call to its destination.

	$c->call();

	# Return a result to the call's source.  Only valid after a call has
	# been received by its destination.

	$c->return(
		type => RESULT_TYPE,
		RESULT_PARAMETERS_IN_KEY_VALUE_PAIRS,
	);

	# Emit a result without a full return.  Only valid after a call has
	# been received by its destination.

	$c->emit(
		type => RESULT_TYPE,
		RESULT_PARAMETERS_IN_KEY_VALUE_PAIRS,
	);

	# Fetch one of a call's parameters.

	my $parameter = $c->arg(PARAMETER_NAME);

=head1 DESCRIPTION

Call is a class to encapsulate an asynchronous call between two
sessions.  It is ultimately intended to replace the ad-hoc message
passing that people create for their components with a single method
that will unify them and improve their interoperability.  I just like
typing "interoperability".

Unfortunately, Call cannot work alone.  The Stage class is a very thin
wrapper for POE::Session, providing some bookkeeping so that calls
know where they are at any given moment.  The  subclass was chosen to
keep this prototype as separate from POE as possible, at least in
these early stages.

=head1 INTERFACE

=over 2

Samples are in the synopsis.

=item new KEY_VALUE_PAIRS

Create a new Call instance.  It requires at least two parameters:
"session" and "event" to identify the call's destination.  Any
remaining key/value pairs are passed as named arguments to the
destination.

=item call

Send the Call object to its destination.  Call objectts represent
asynchronous requests and their responses.  They aren't actually sent
to their destinations until the call() method is invoked.

The call() method is not necessary.  It exists for the sake of
prototyping.  Later it will be subsumed into Call's private interface,
and nicer public methods will emerge.

In the meanwhile, remember that a Call isn't actually sent to its
destination until you call call().

=item return KEY_VALUE_PAIRS

Return a response to the Call's creator, and terminate the Call.
return() requires one named parameter: "type".  A session can return
many different types of results from a single Call.  The "type" helps
to identify which kind of result has occurred.  For example:

	$c->return(
		type    => "error",
		err_num => $!+0,
		err_str => "$!",
	);

or

	$c->return(
		type    => "success",
		address => $address,
	);

=item on RESULT_TYPE => MY_EVENT_NAME

Watch for RESULT_TYPE from the Call, and trigger the handler for
MY_EVENT_NAME when it arrives.  ARG0 of the handler will be a new Call
object representing the return value.

A Call can be sent without on() ever being used.  Likewise, on() can
be used multiple times to watch for several types of result.

	$c->on( success => "success_event" );
	$c->on( failure => "failure_event" );

=item cancel

Cancel a Call.  The caller can use this to stop a request before a
result has been generated.  It's not tested, and it's likely to be
broken because I haven't considered the semantics (or mechanics) of
canceling calls.

=item emit KEY_VALUE_PAIRS

Return a response to the Call's creator, but do not terminate the
Call.  Used to send multiple responses to a caller from a single
request.

Usage is identical to return().

=item arg PARAMETER_NAME

Recall an argument/parameter from a Call.

	my $address = $c->arg("address");
	print "Call failed: ", $c->arg("err_str'), "\n";

=back

=head1 FUTURE

To be determined.  Some ways you can help:

Write an interaction prototype to examine how Call works in a
particular situation.  Perhaps you've already written a component, and
you want to be sure Call supports its interaction model.

Tell your friends about it.  Or tell me, if it sucks.

Talk about it on POE's mailing list, or in irc.perl.org #poe.

Hire the author to develop it and other nifty technologies that may
revolutionize the way you use Perl at work.

=head1 LICENSE AND AUTHOR

Call is Copyright 2005 by Rocco Caputo.  All rights are reserved.  You
may modify and distribute this code under the same terms as Perl
itself.

=cut
