# $Id$

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
use constant REQ_CONTEXT        => 10;  # Request storage scope.
use constant REQ_PARENT_REQUEST => 11;  # The request that begat this one.
use constant REQ_DELIVERY_REQ   => 12;  # "req" to deliver to the method.
use constant REQ_DELIVERY_RSP   => 13;  # "rsp" to deliver to the method.
use constant REQ_TYPE           => 14;  # Request type?

use Exporter;
use base qw(Exporter);
@POE::Request::EXPORT_OK = qw(
	REQ_CONTEXT
	REQ_CREATE_STAGE
	REQ_DELIVERY_REQ
	REQ_DELIVERY_RSP
	REQ_PARENT_REQUEST
	REQ_TARGET_METHOD
	REQ_TARGET_STAGE
	REQ_TYPE
	@EXPORT_OK
);

my @request_stack;

sub _get_current_request {
	return 0 unless @request_stack;
	return $request_stack[-1];
}

# Push the request on the request stack, making this one active or
# current.

sub _push {
	my ($self, $request) = @_;
	push @request_stack, $request;
}

sub _invoke {
	my ($self, $method) = @_;

	DEBUG and warn(
		"\t$self invoking $self->[REQ_TARGET_STAGE] method $method:\n",
		"\t\tMy req  = $self->[REQ_TARGET_STAGE]{req}\n",
		"\t\tMy rsp  = $self->[REQ_TARGET_STAGE]{rsp}\n",
		"\t\tPar req = $self->[REQ_PARENT_REQUEST]\n",
		"\t\tContext = $self->[REQ_CONTEXT]\n",
	);

	$self->[REQ_TARGET_STAGE]->$method($self->[REQ_ARGS]);
}

sub _pop {
	my ($self, $request) = @_;
	confess "not defined?!" unless defined $request;
	my $pop = pop @request_stack;
	confess "bad pop($pop) not request($request)" unless $pop == $request;
}

sub _get_context {
	return shift()->[REQ_CONTEXT];
}

sub _request_constructor {
	my ($class, $args) = @_;
	my ($package, $filename, $line) = caller(1);

	foreach my $param (qw(_stage _method)) {
		next if exists $args->{$param};
		croak "$class is missing the '$param' parameter";
	}

	# TODO - What's the "right" way to make fields inheritable without
	# clashing in Perl?

	my $self = bless [
		delete $args->{_stage},   # REQ_TARGET_STAGE
		delete $args->{_method},  # REQ_TARGET_METHOD
		{ },                      # REQ_CHILD_REQUESTS
		{ },                      # REQ_RESOURCES
		$package,                 # REQ_CREATE_PKG
		$filename,                # REQ_CREATE_FILE
		$line,                    # REQ_CREATE_LINE
		0,                        # REQ_CREATE_STAGE
		{ },                      # REQ_ARGS
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

sub new {
	my ($class, %args) = @_;

	my $self = $class->_request_constructor(\%args);

	# Gather up the type/method mapping for any responses to this
	# request.

	my %returns;
	foreach (keys %args) {
		next unless /^_on_(\S+)$/;
		$returns{$1} = delete $args{$_};
	}
	$self->[REQ_RETURNS] = \%returns;

	# Set the parent request to be the currently active request.
	# New request = new context.

	$self->[REQ_PARENT_REQUEST] = POE::Request->_get_current_request();
	$self->[REQ_CONTEXT] = { };

	# If we have a parent request, then we need to associate this new
	# request with it.  The references between parent and child requests
	# are all weak because it's up to the creator to decide when
	# destruction happens.

	if ($self->[REQ_PARENT_REQUEST]) {
		$self->[REQ_CREATE_STAGE] = $self->[REQ_PARENT_REQUEST][REQ_TARGET_STAGE];
		weaken $self->[REQ_CREATE_STAGE];

		$self->[REQ_PARENT_REQUEST][REQ_CHILD_REQUESTS]{$self} = $self;
		weaken $self->[REQ_PARENT_REQUEST][REQ_CHILD_REQUESTS]{$self};
	}

	DEBUG and warn(
		"$self->[REQ_PARENT_REQUEST] created $self:\n",
		"\tMy parent request = $self->[REQ_PARENT_REQUEST]\n",
		"\tDelivery request  = $self\n",
		"\tDelivery response = 0\n",
		"\tDelivery context  = $self->[REQ_CONTEXT]\n",
	);

	$self->_assimilate_args(%args);
	$self->_send_to_target();

	return $self;
}

sub _assimilate_args {
	my ($self, %args) = @_;

	# Process additional arguments.  The subclass should remove all
	# adorned arguments it uses.  Any remaining are considered a usage
	# error.

	$self->init(\%args);

	foreach my $param (keys %args) {
		croak ref($self) . " has an illegal '$param' parameter" if $param =~ /^_/;
	}

	# Copy the remaining arguments into the object.

	$self->[REQ_ARGS] = { %args };
}

sub init {
	# Virtual base method.  Do nothing by default.
}

# Deliver the request to its destination.  Requesting down into a
# stage, so req is the request that invoked the method, and _rsp is
# zero because there's no downward path from here.

sub deliver {
	my ($self, $method) = @_;

	$self->_push($self);

	$self->[REQ_TARGET_STAGE]{req} = $self;
	$self->[REQ_TARGET_STAGE]{rsp} = 0;

	$self->_invoke($method || $self->[REQ_TARGET_METHOD]);

	my $old_rsp = delete $self->[REQ_TARGET_STAGE]{rsp};
	my $old_req = delete $self->[REQ_TARGET_STAGE]{req};

	die "bad rsp" unless $old_rsp == 0;
	die "bad req" unless $old_req == $self;

	$self->_pop($self);
}

# Return a response to the requester.  The response occurs in the
# requester's original context, somehow.

sub return {
	my ($self, %args) = @_;
	$self->_emit("POE::Request::Return", %args);
	$self->cancel();
}

sub emit {
	my ($self, %args) = @_;
	$self->_emit("POE::Request::Emit", %args);
}

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
		delete $self->[REQ_PARENT_REQUEST][REQ_CHILD_REQUESTS]{$self};
		$self->[REQ_PARENT_REQUEST] = 0;
	}
}

sub _emit {
	my ($self, $class, %args) = @_;

	# Where does the message go?
	# TODO - Have croak() reference the proper package/file/line.

	my $parent_stage = $self->[REQ_CREATE_STAGE];
	confess "Can't emit message: Requester is not a POE::Stage class" unless (
		$parent_stage
	);

	# Pull out the message type, and map it to a method.

	my $message_type = delete $args{_type};
	croak "Message must have a _type parameter" unless defined $message_type;
	my $message_method = (
		(exists $self->[REQ_RETURNS]{$message_type})
		? $self->[REQ_RETURNS]{$message_type}
		: "unknown_type"
	);

	# Reconstitute the parent's context.
	my $parent_context;
	my $parent_request = $self->[REQ_PARENT_REQUEST];
	croak "Cannot emit message: The requester has no context" unless (
		$parent_request
	);

	my $response = $class->new(
		%args,
		_stage   => $parent_stage,
		_method  => $message_method,
		_type    => $message_type,
	);
}

1;
