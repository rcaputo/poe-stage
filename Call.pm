# $Id$

package Call;

use warnings;
use strict;

use POE::Kernel;

use Carp qw(croak carp confess);
use Scalar::Util qw(weaken);

sub STATE_UNSENT    () { 0x01 }
sub STATE_SENT      () { 0x02 }
sub STATE_RECEIVED  () { 0x04 }
sub STATE_RETURNING () { 0x08 }
sub STATE_RETURNED  () { 0x10 }
sub STATE_CANCELED  () { 0x20 }
sub STATE_DESTROYED () { 0x40 }

sub RET_STAGE  () { 0 }
sub RET_METHOD () { 1 }

sub DEBUG () { 0 }

sub new {
	my ($class, %args) = @_;

	my ($package, $filename, $line) = caller();

	foreach my $param (qw(_stage _method)) {
		next if exists $args{$param};
		croak "$class is missing the '$param' parameter";
	}

	# The parent call is the call that creates this one.
	my $parent_call = Call->_get_current_call();

	my $self = bless {
		_dst_stage    => delete $args{_stage},
		_dst_method   => delete $args{_method},
		_state        => STATE_UNSENT,
		_returns      => { },
		_parent_call  => $parent_call,
		_child_calls  => { },
		_resources    => { },
		_create_pkg   => $package,
		_create_fil   => $filename,
		_create_lin   => $line,
	}, $class;

	# If we have a parent call, then our source stage is its destination
	# stage.  This must occur after any fixups for return() and whatnot.

	if ($parent_call) {
		$self->{_src_stage} = $parent_call->get_dst_stage();
	}
	else {
		$self->{_src_stage} = 0;
	}

	# Move the user arguments in, with checking.

	foreach my $param (keys %args) {
		croak "$class has an illegal '$param' parameter" if $param =~ /^_/;
		$self->{$param} = $args{$param};
	}

	if (DEBUG) {
		warn "dest stage = $self->{_dst_stage}";
		warn "dest meth  = $self->{_dst_method}";
		warn "parent     = $parent_call";
	}

	# If the call goes to an :async Stage method, then it starts a new
	# request context.

	if (ref($self->{_dst_stage})->is_async($self->{_dst_method})) {
		$self->{_context} = { };
	}

	# The call has a parent.

	elsif ($parent_call) {

		# It's the same as the current stage.  Share its context.

		if ($parent_call and $self->{_src_stage} == $self->{_dst_stage}) {
			$self->{_context} = $parent_call->{_context};
		}

		# The parent call is returning.  Scan back through the call chain
		# for the most recent call from the destination.  Use that context.

		elsif ($parent_call->get_state() & STATE_RETURNING) {
			my $scan_back = $parent_call;

			while ($scan_back and $scan_back->{_src_stage} != $self->{_dst_stage}) {
				$scan_back = $scan_back->{_parent_call};
			}

			if ($scan_back) {
				$self->{_context} = $scan_back->{_context};
			}
			else {
				croak "return can't find the matching call";
			}
		}

		# It's a new synchronous stage.  Reuse the current context.
		# TODO - This may not be appropriate.

		else {
			$self->{_context} = $parent_call->{_context};
		}
	}

	# Start a new context for a new call.

	else {
		$self->{_context} = { };
	}

	# The pointers to children must be weak so the child calls can
	# DESTROY at appropriate times.
	if ($parent_call) {
		$parent_call->{_child_calls}{$self} = $self;
		weaken $parent_call->{_child_calls}{$self};
	}

	return $self;
}

sub get_state {
	my $self = shift;
	return $self->{_state};
}

sub get_dst_stage {
	my $self = shift;
	return $self->{_dst_stage};
}

sub context {
	my $self = shift;
	my $key  = shift;
	return $self->{_context}{$key} = shift if @_;
	return $self->{_context}{$key};
}

sub on {
	my ($self, %args) = @_;

#	unless ($self->{_state} & STATE_UNSENT) {
#		croak "can't call on() once a Call has been sent";
#	}

	foreach my $param (qw(type method)) {
		next if exists $args{$param};
		croak "$self is missing the '$param' parameter";
	}

	my $type   = delete $args{type};
	my $method = delete $args{method};

	my $parent_call = $self->{_parent_call};
	confess "no parent call" unless $parent_call;

	my $parent_stage = $parent_call->{_dst_stage};

	push @{$self->{_returns}{$type}}, [
		$parent_stage,  # RET_STAGE
		$method,        # RET_METHOD
	];

#	warn "+ incrementing for $current_stage -> $method";
	$poe_kernel->refcount_increment($parent_stage->get_sid(), "call");
}

# TODO - Send a standard canceled message?
sub end { goto &cancel }
sub cancel {
	my $self = shift;

	if ($self->{_state} & STATE_CANCELED) {
		carp "ignored cancel() on an already canceled Call";
		return;
	}

	if ($self->{_state} & STATE_RETURNING) {
		carp "ignored cancel() on a returning Call";
		return;
	}

	if ($self->{_state} & STATE_RETURNED) {
		carp "ignored cancel() on a returned Call";
		return;
	}

	if ($self->{_state} & STATE_DESTROYED) {
		croak "can't cancel() a destroyed Call";
	}

	# Propagate cancels depth-first.  The block eval is to avoid
	# problems canceling dead children due to weakened references.
	foreach my $child (values %{$self->{_child_calls}}) {
		eval { $child->cancel() };
	}

	$self->{_state} = STATE_CANCELED;

	# XXX - I'm not sure about the timing of _stop_returns() vs.
	# propagating cancels.
	$self->_stop_returns();
}

sub _stop_returns {
	my $self = shift;

	while (my ($type, $returns) = each %{$self->{_returns}}) {
		foreach my $return (@$returns) {
			my ($stage, $method) = @$return;
#			warn "- decrementing for $stage -> $method";
			$poe_kernel->refcount_decrement($stage->get_sid(), "call");
		}
	}

	# Prevent duplicate cleanup.
	$self->{_returns} = { };
}

#sub _start_returns {
#	my $self = shift;
#
#	while (my ($type, $returns) = each %{$self->{_returns}}) {
#		foreach my $return (@$returns) {
#			my ($stage, $method) = @$return;
#			warn "+ incrementing for $stage -> $method";
#			$poe_kernel->refcount_increment($stage->get_sid(), "call");
#		}
#	}
#}

sub call {
	my $self = shift;

	unless ($self->{_state} & STATE_UNSENT) {
		croak "a Call must be unsent to call() it";
	}

#	warn "$self->{_dst_stage}";
	$poe_kernel->post($self->{_dst_stage}->get_sid(), "stage_call", $self);

	$self->{_state} = STATE_SENT;
}

sub return {
	my ($self, %args) = @_;

	unless (exists $args{type}) {
		croak "return() requires a 'type'";
	}

	unless ($self->{_state} & STATE_RECEIVED) {
		if ($self->{_state} & STATE_RETURNING) {
			croak "can't call return() twice on a single Call";
		}
		if ($self->{_state} & STATE_CANCELED) {
			croak "can't call return() on a canceled Call";
		}
		if ($self->{_state} & STATE_DESTROYED) {
			croak "can't call return() on a destroyed Call";
		}
		croak "can't call return() until a Call has been received";
	}

	$self->{_state} = STATE_RETURNING;
	$self->_bubble(%args);
	$self->_stop_returns();
}

sub emit {
	my ($self, %args) = @_;

	unless (exists $args{type}) {
		croak "$self requires a 'type'";
	}

	unless ($self->{_state} & STATE_RECEIVED) {
		if ($self->{_state} & STATE_CANCELED) {
			croak "can't call emit() on a canceled Call";
		}
		if ($self->{_state} & STATE_DESTROYED) {
			croak "can't call emit() on a destroyed Call";
		}
		croak "can't call emit() until a Call has been received";
	}

	$self->_bubble(%args);
}

sub _receive {
	my $self = shift;

	unless ($self->{_state} & STATE_SENT) {
		croak "can't receive() a Call that is not in transit";
	}

	$self->{_state} = STATE_RECEIVED;
}

# TODO - Need a Call chain and method/exception bubbling upwards.
# TODO - Make sure called-back session runs in its previous context.

sub _bubble {
	my ($self, %args) = @_;

	my $type = $args{type} || die;
	return unless exists $self->{_returns}{$type};

	my $parent = $self->{_parent_call};

	foreach my $return (@{$self->{_returns}{$type}}) {
		my ($stage, $method) = @$return;

#		use YAML;
#		warn "!!!!!!!!!!!!!!!!!!!!\n",YAML::Dump(\%args), "!!!!!!!!!! ";
#		warn "!!!!!!!!!! also stage($stage) method($method)";

		$stage->$method(%args);
#		my $c = Call->new(
#			stage    => $stage,
#			method   => $method,
#			%args,
#		);
#
##		my $call = $c;
##		my $indent = 0;
##		while ($call) {
##			my $parent = $call->{_parent_call};
##			warn( ("  " x $indent++), "$call has parent $parent\n" );
##			$call = $parent;
##		}
#
#		$c->call();
	}
}

sub _detach_from_parent {
	my $self = shift;
	if ($self->{_parent_call}) {
		delete $self->{_parent_call}{child_calls}{$self};
		$self->{_parent_call} = undef;
	}
}

sub DESTROY {
	my $self = shift;
	$self->{_state} = STATE_DESTROYED;
	$self->_detach_from_parent();
	$self->_stop_returns();
}

my @call_stack;

my $i = 1;

sub _activate {
	my $self = shift;
	push @call_stack, $self;

	use YAML;
	YAML::DumpFile("dump." . $i++, \@call_stack);
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
	return 0 unless @call_stack;
	return $call_stack[-1];
}

sub _get_current_context {
	my $current_call = Call->_get_current_call();
	return $current_call->{_context};
}

# Manage resources.

sub register_resource {
	my ($self, $resource) = @_;
	$self->{_resources}{$resource} = $resource;
}

sub unregister_resource {
	my ($self, $resource) = @_;
	delete $self->{_resources}{$resource};
}

sub find_resource {
	my ($self, $resource) = @_;
	return $self->{_resources}{$resource};
}

sub destination {
	my $self = shift;
	return ($self->{_dst_stage}, $self->{_dst_method});
}

sub destination_stage {
	my $self = shift;
	return $self->{_dst_stage};
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
		stage  => DESTINATION_STAGE,
		method => DESTINATION_METHOD_NAME,
		METHOD_PARAMETERS_IN_KEY_VALUE_PAIRS,
	);

	# Watch for a type of result.  Only valid before a call is sent to
	# its destination.  A single Call can have multiple watchers.

	$c->on(
		RESULT_TYPE => MY_METHOD_NAME,
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

	my $parameter = $c->{PARAMETER_NAME};

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
"stage" and "method" to identify the call's destination.  Any
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

=item on RESULT_TYPE => MY_METHOD_NAME

Watch for RESULT_TYPE from the Call, and trigger the handler for
MY_METHOD_NAME when it arrives.  ARG0 of the handler will be a new Call
object representing the return value.

A Call can be sent without on() ever being used.  Likewise, on() can
be used multiple times to watch for several types of result.

	$c->on( success => "success_method" );
	$c->on( failure => "failure_method" );

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
