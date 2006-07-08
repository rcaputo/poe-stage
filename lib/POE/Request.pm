# $Id$

=head1 NAME

POE::Request - a common message class for POE::Stage

=head1 SYNOPSIS

	# Note, this is not a complete program.
	# See the distribution's examples directory.

	my $request :Req = POE::Request->new(
		method    => "method_name",           # invoke this method
		stage     => $self->{stage_object},   # of this stage
		on_one    => "do_one",    # map a "one" response to method
		args      => {
			param_1 => 123,         # with this parameter
			param_2 => "abc",       # and this one
		}
	);

	# Handle a "one" response.
	sub do_one {
		my ($self, $args) = @_;
		print "$args->{param_1}\n";  # 123
		print "$args->{param_2}\n";  # abc
		...;
		$self->{req}->return( type => "one", moo => "retval" );
	}

	# Handle one's return value.
	sub do_one {
		my ($self, $args) = @_;
		print "$args->{moo}\n";  # retval
	}

=head1 DESCRIPTION

POE::Request objects are the messages passed between POE::Stage
objects.  They include a destination (stage and method), values to
pass to the destination method, mappings between return message types
and the source methods to handle them, and possibly other parameters.

POE::Request includes methods that can be used to send responses to an
initiating request.  It internally uses POE::Request subclasses to
encapsulate the resulting messages.

Requests may also be considered the start of two-way dialogues.  The
emit() method may be used by an invoked stage to send back an interim
response, and then the caller may use recall() on the interim response
to send an associated request back to the invoked stage.

Each POE::Request object can be considered as a continuation.
Variables may be associated with either the caller's or invocant
stage's side of a request.  Values associated with one side are not
visible to the other side, even if they share the same variable name.
The associated variables and their values are always in scope when
that side of the request is active.  Variables associated with a
request are destroyed when the request is canceled or completed.

For example, a sub-request is created within the context of the
current request.

	sub some_request_sender {
		my $foo :Req = POE::Request->new(...);
	}

Whenever the same request is active, C<my $foo :Req;> imports the
field (with its current value) in the current scope.

Furthermore, fields may be associated with a particular request.
These will be available again in response handlers using the special
":Rsp" attribute:

	sub some_request_sender {
		my $foo :Req = POE::Request->new(...);
		my $foo_field :Req($foo) = "a sample value";
	}

	sub some_response_handler {
		my $foo_field :Rsp;
		print "$foo_field\n";   # "a sample value"
	}

=cut

package POE::Request;

use warnings;
use strict;

use Carp qw(croak confess);
use POE::Kernel;
use Scalar::Util qw(weaken);

use constant DEBUG => 0;

use constant REQ_TARGET_STAGE   =>  0;  # Stage to be invoked.
use constant REQ_TARGET_METHOD  =>  1;  # Method to invoke on the stage.
use constant REQ_CHILD_REQUESTS =>  2;  # Requests begotten from this one.
use constant REQ_RESOURCES      =>  3;  # Resources created in this request.
use constant REQ_CREATE_PKG     =>  4;  # Debugging.
use constant REQ_CREATE_FILE    =>  5;  # ... more debugging.
use constant REQ_CREATE_LINE    =>  6;  # ... more debugging.
use constant REQ_CREATE_STAGE   =>  7;  # ... more debugging.
use constant REQ_ARGS           =>  8;  # Parameters of this request.
use constant REQ_RETURNS        =>  9;  # Return type/method map.
use constant REQ_PARENT_REQUEST => 10;  # The request that begat this one.
use constant REQ_DELIVERY_REQ   => 11;  # "req" to deliver to the method.
use constant REQ_DELIVERY_RSP   => 12;  # "rsp" to deliver to the method.
use constant REQ_TYPE           => 13;  # Request type?
use constant REQ_ID             => 14;  # Request ID.

use Exporter;
use base qw(Exporter);
BEGIN {
	@POE::Request::EXPORT_OK = qw(
		REQ_CREATE_STAGE
		REQ_DELIVERY_REQ
		REQ_DELIVERY_RSP
		REQ_ID
		REQ_PARENT_REQUEST
		REQ_TARGET_METHOD
		REQ_TARGET_STAGE
		REQ_TYPE
		@EXPORT_OK
	);
}

use POE::Stage::TiedAttributes qw(REQUEST RESPONSE);

my $last_request_id = 0;
my %active_request_ids;

sub _allocate_request_id {
	1 while (
		exists $active_request_ids{++$last_request_id} or $last_request_id == 0
	);
	$active_request_ids{$last_request_id} = 1;
	return $last_request_id;
}

sub _reallocate_request_id {
	my ($self, $id) = @_;
	croak "id $id can't be reallocated if it isn't allocated" unless (
		$active_request_ids{$id}++
	);
	return $id;
}

# Returns true if the ID is freed.
sub _free_request_id {
	my $id = shift;

	# This croak() actually seems to help with a memory leak.
	croak "$id isn't allocated" unless $active_request_ids{$id};

	return 0 if --$active_request_ids{$id};
	delete $active_request_ids{$id};
	return 1;
}

sub get_id {
	my $self = shift;
	return $self->[REQ_ID];
}

use overload (
	'""' => sub {
		my $id = shift()->[REQ_ID];
		return "(request $id)";
	},
	'0+' => sub {
		my $id = shift()->[REQ_ID];
		return $id;
	},
	fallback => 1,
);

sub DESTROY {
	my $self = shift;
	my $id = $self->[REQ_ID];

	if (_free_request_id($id)) {
		tied(%{$self->[REQ_CREATE_STAGE]})->_request_context_destroy($id)
			if $self->[REQ_CREATE_STAGE];
		tied(%{$self->[REQ_TARGET_STAGE]})->_request_context_destroy($id)
			if $self->[REQ_TARGET_STAGE];
	}
}

use constant RS_REQUEST => 0;
use constant RS_STAGE   => 1;
use constant RS_METHOD  => 2;

my @request_stack;

sub _get_current_request {
	return 0 unless @request_stack;
	return $request_stack[-1][RS_REQUEST];
}

sub _get_current_stage {
	return 0 unless @request_stack;
	return $request_stack[-1][RS_STAGE];
}

# Push the request on the request stack, making this one active or
# current.

# TODO - Leolo suggests using true globals and localizing them at
# dispatch time.  This might be faster despite the penalty of using a
# true global.  It may also be possible to make $req and $rsp magic
# variables that POE::Stage exports, but would the exported versions
# of globals refer to the global or the localized value?  It appears
# that localization's not an option.  See lab/local-scoped-state.perl
# for a test case.

sub _push {
	my ($self, $request, $stage, $method) = @_;
	push @request_stack, [
		$request,     # RS_REQUEST
		$stage,       # RS_STAGE
		$method,      # RS_METHOD
	];
}

sub _invoke {
	my ($self, $method, $override_args) = @_;

	DEBUG and warn(
		"\t$self invoking $self->[REQ_TARGET_STAGE] method $method:\n",
		"\t\tMy req  = $self->[REQ_TARGET_STAGE]{req}\n",
		"\t\tMy rsp  = $self->[REQ_TARGET_STAGE]{rsp}\n",
		"\t\tPar req = $self->[REQ_PARENT_REQUEST]\n",
	);

	$self->[REQ_TARGET_STAGE]->$method(
		$override_args || $self->[REQ_ARGS]
	);
}

sub _pop {
	my ($self, $request, $stage, $method) = @_;
	confess "not defined?!" unless defined $request;
	my ($pop_request, $pop_stage, $pop_method) = @{pop @request_stack};
#	confess "bad pop($pop_request) not request($request)" unless (
#		$pop_request == $request
#	};
}

sub _request_constructor {
	my ($class, $args) = @_;
	my ($package, $filename, $line) = caller(1);

	foreach my $param (qw(stage method)) {
		next if exists $args->{$param};
		croak "$class is missing the '$param' parameter";
	}

	# TODO - What's the "right" way to make fields inheritable without
	# clashing in Perl?

	my $self = bless [
		delete $args->{stage},        # REQ_TARGET_STAGE
		delete $args->{method},       # REQ_TARGET_METHOD
		{ },                          # REQ_CHILD_REQUESTS
		{ },                          # REQ_RESOURCES
		$package,                     # REQ_CREATE_PKG
		$filename,                    # REQ_CREATE_FILE
		$line,                        # REQ_CREATE_LINE
		0,                            # REQ_CREATE_STAGE
		{ },                          # REQ_ARGS
	], $class;

	return $self;
}

# Send the request to its destination.
sub _send_to_target {
	my $self = shift;
	Carp::confess "whoops" unless $self->[REQ_TARGET_STAGE];
	$poe_kernel->post(
		$self->[REQ_TARGET_STAGE]->_get_session_id(), "stage_request", $self
	);
}

=head1 PUBLIC METHODS

Request methods are called directly on the objects themselves.

=head2 new PARAM => VALUE, PARAM => VALUE, ...

Create a new POE::Request object.  The request will automatically be
sent to its destination.  Factors on the local or remote process, or
pertaining to the network between them, may prevent the request from
being delivered immediately.

POE::Request->new() requires at least two parameters.  "stage"
contains the POE::Stage object that will receive the request.
"method" is the method to call when the remote stage handles the
request.  The stage may merely be a local proxy for a remote object,
but this feature has yet to be defined.

Parameters for the message's destination can be supplied in the
optional "args" parameter.  These parameters will be passed untouched
to the message's destination's $args parameter.

POE::Request->new() returns an object which must be saved.  Destroying
a request object will cancel the request and automatically free all
data and resources associated with it, including sub-stages and
sub-requests.  This is ensured by storing sub-stages and sub-requests
within the context of higher-level requests.

Instances of POE::Request subclasses, such as those created by
$request->return(), do not need to be saved.  They are ephemeral
responses and re-requests, and their lifespans do not control the
lifetime duration of the original request.

=cut

sub new {
	my ($class, %args) = @_;

	my $self = $class->_request_constructor(\%args);

	# Gather up the type/method mapping for any responses to this
	# request.

	my %returns;
	foreach (keys %args) {
		next unless /^on_(\S+)$/;
		$returns{$1} = delete $args{$_};
	}

	$self->[REQ_RETURNS] = \%returns;

	# Set the parent request to be the currently active request.
	# New request = new context.

	# XXX - Only used for the request object?
	$self->[REQ_PARENT_REQUEST] = POE::Request->_get_current_request();
	$self->[REQ_ID] = $self->_allocate_request_id();

	# If we have a parent request, then we need to associate this new
	# request with it.  The references between parent and child requests
	# are all weak because it's up to the creator to decide when
	# destruction happens.

	if ($self->[REQ_PARENT_REQUEST]) {
		my $parent_data = $self->[REQ_PARENT_REQUEST];
		$self->[REQ_CREATE_STAGE] = $parent_data->[REQ_TARGET_STAGE];
		weaken $self->[REQ_CREATE_STAGE];

		$parent_data->[REQ_CHILD_REQUESTS]{$self} = $self;
		weaken $parent_data->[REQ_CHILD_REQUESTS]{$self};
	}

	DEBUG and warn(
		"$self->[REQ_PARENT_REQUEST] created $self:\n",
		"\tMy parent request = $self->[REQ_PARENT_REQUEST]\n",
		"\tDelivery request  = $self\n",
		"\tDelivery response = 0\n",
	);

	$self->_assimilate_args($args{args} || {});
	$self->_send_to_target();

	return $self;
}

sub _assimilate_args {
	my ($self, $args) = @_;

	# Process additional arguments.  The subclass should remove all
	# adorned arguments it uses.  Any remaining are considered a usage
	# error.

	$self->init($args);

	# Copy the remaining arguments into the object.

	$self->[REQ_ARGS] = { %$args };
}

=head2 init HASHREF

The init() method receives the request's constructor $args before they
are processed and stored in the request.  Its timing gives it the
ability to modify members of $args, add new ones, or remove old ones.

Custom POE::Request subclasses may use init() to verify that
parameters are correct.  Currently init() must throw an exeception
with die() to signal some form of failure.

=cut

sub init {
	# Virtual base method.  Do nothing by default.
}

# Deliver the request to its destination.  Requesting down into a
# stage, so req is the request that invoked the method, and rsp is
# zero because there's no downward path from here.
#
# TODO - Rename _deliver since this is a friend method.

sub deliver {
	my ($self, $method, $override_args) = @_;

	my $target_stage = $self->[REQ_TARGET_STAGE];
	my $target_stage_data = tied(%$target_stage);

	my $delivery_req = $self->[REQ_DELIVERY_REQ] || $self;
	$target_stage_data->[REQUEST]  = $delivery_req;
	$target_stage_data->[RESPONSE] = 0;

	my $target_method = $method || $self->[REQ_TARGET_METHOD];
	$self->_push($self, $target_stage, $target_method);

	$self->_invoke($target_method, $override_args);

	$self->_pop($self, $target_stage, $target_method);

	my $old_rsp = delete $target_stage_data->[RESPONSE];
	my $old_req = delete $target_stage_data->[REQUEST];

#	die "bad rsp" unless $old_rsp == 0;
#	die "bad req" unless $old_req == $delivery_req;
}

# Return a response to the requester.  The response occurs in the
# requester's original context, somehow.

=head2 return type => RETURN_TYPE, RETURN_MEMBER => RETURN_VALUE, ...

Cancels the current POE::Request object, invalidating it for future
operations, and internally creates a return message via
POE::Request::Return.  This return message is initialized with pairs
of RETURN_MEMBER => RETURN_VALUE parameters.  It is automatically (if
not immediately) sent back to the POE::Stage that created the original
request.

Please see POE::Request::Return for details about return messages.

If the type of message is not selected, it defaults to "return".

=cut

sub return {
	my ($self, %args) = @_;

	# Default return type
	$args{type} ||= "return";

	$self->_emit("POE::Request::Return", %args);
	$self->cancel();
}

=head2 emit type => EMIT_TYPE, EMIT_MEMBER => EMIT_VALUE, ...

Creates a POE::Request::Emit object initialized with the pairs of
EMIT_MEMBER => EMIT_VALUE parameters.  The emitted response will be
automatically sent back to the creator of the request being invoked.

Unlike return(), emit() does not cancel the current request, and
emitted messages can be replied.  It is designed to send back an
interim response but not end the request.

If the type of message is not selected, it defaults to "emit".

=cut

sub emit {
	my ($self, %args) = @_;
	# Default return type
	$args{type} ||= "emit";

	$self->_emit("POE::Request::Emit", %args);
}

=head2 cancel

Explicitly cancel a request.  Mainly used by the invoked stage, not
the caller.  Normally destroying the request object is sufficient, but
this may only be done by the caller.  The request's receiver can call
cancel() however.

As mentioned earlier, canceling a request frees up the data associated
with that request.  Cancellation and destruction cascade through the
data associated with a request and any sub-stages and sub-requests.
This efficiently and automatically releases all resources associated
with the entire request tree rooted with the canceled request.

A canceled request cannot generate a response.  If you are tempted to
follow emit() with a cancel(), then use return() instead.  The
return() method is essentially an emit() and cancel() together.

=cut

sub cancel {
	my $self = shift;

	# Cancel all the children first.

	foreach my $child (values %{$self->[REQ_CHILD_REQUESTS]}) {
		eval {
			$child->cancel();
		};
	}

	# A little sanity check.  We should have no children once they're
	# canceled.
	die "canceled parent has children left" if (
		keys %{$self->[REQ_CHILD_REQUESTS]}
	);

	# Disengage from our parent.
	# TODO - Use a mutator rather than grope inside the parent object.

	if ($self->[REQ_PARENT_REQUEST]) {
		my $parent_data = $self->[REQ_PARENT_REQUEST];
		delete $parent_data->[REQ_CHILD_REQUESTS]{$self};
		$self->[REQ_PARENT_REQUEST] = 0;
	}

	# Weaken the target stage?
	weaken $self->[REQ_TARGET_STAGE];
}

sub _emit {
	my ($self, $class, %args) = @_;

	# Where does the message go?
	# TODO - Have croak() reference the proper package/file/line.

	# The message type is important for finding the appropriate method,
	# either on the sending stage or its destination.

	my $message_type = delete $args{type};
	croak "Message must have a type parameter" unless defined $message_type;

	# If the caller has an on_my_$mesage_type method, deliver there
	# immediately.
	my $emitter = $self->[REQ_TARGET_STAGE];
	my $emitter_method = "on_my_$message_type";
	if ($emitter->can($emitter_method)) {
		# TODO - This is probably wrong.  For example, do we need
		# _push/_pop around _invoke.
		return $self->_invoke($emitter_method, \%args);
	}

	# Otherwise we propagate the message back to the request's sender.
	my $parent_stage = $self->[REQ_CREATE_STAGE];
	confess "Can't emit message: Requester is not a POE::Stage class" unless (
		$parent_stage
	);

	my $message_method = (
		(exists $self->[REQ_RETURNS]{$message_type})
		? $self->[REQ_RETURNS]{$message_type}
		: "unknown_type($message_type)"
	);

	# Reconstitute the parent's context.
	my $parent_context;
	my $parent_request = $self->[REQ_PARENT_REQUEST];
	croak "Cannot emit message: The requester has no context" unless (
		$parent_request
	);

	my $response = $class->new(
		args    => { %{ $args{args} || {} } },
		stage   => $parent_stage,
		method  => $message_method,
		type    => $message_type,
	);
}

1;

=head1 DESIGN GOALS

Requests are designed to encapsulate messages passed between stages,
so you don't have to.  It's our hope that providing a standard,
effective message passing system will maximize interoperability
between POE stages.

Requests may be subclassed.

At some point in the future, request classes may be used as message
types rather than C<<type => $type>> parameters.  More formal
POE::Stage interfaces may take advantage of explicit message typing in
the future.

=head1 BUGS

See http://thirdlobe.com/projects/poe-stage/report/1 for known issues.
See http://thirdlobe.com/projects/poe-stage/newticket to report one.

C<:Req> and C<:Rsp> must be discussed in greater detail, perhaps in
one or more tutorials.

=head1 SEE ALSO

POE::Request has subclasses that are used internally.  While they
share the same interface as POE::Request, all its methods are not
appropriate in all its subclasses.

Please see POE::Request::Upward for a discussion of response events,
and how they are mapped to method calls by the requesting stage.
POE::Request::Return and POE::Request::Emit are specific kinds of
upward-facing response messages.

L<POE::Request::Return>, L<POE::Request::Recall>,
L<POE::Request::Emit>, and L<POE::Request::Upward>.

=head1 AUTHORS

Rocco Caputo <rcaputo@cpan.org>.

=head1 LICENSE

POE::Request is Copyright 2005-2006 by Rocco Caputo.  All rights are
reserved.  You may use, modify, and/or distribute this module under
the same terms as Perl itself.

=cut
