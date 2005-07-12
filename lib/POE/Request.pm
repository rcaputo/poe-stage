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

use POE::Request::TiedAttributes;
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
	return 0 if --$active_request_ids{$id};
	delete $active_request_ids{$id};
	return 1;
}

use overload (
	'""' => sub {
		my $id = tied(%{shift()})->[REQ_ID];
		return "(request \#$id)";
	},
	'0+' => sub {
		my $id = tied(%{shift()})->[REQ_ID];
		return $id;
	},
	fallback => 1,
);

sub DESTROY {
	my $self = shift;
	my $inner_object = tied %$self;
	return unless $inner_object;
	my $id = $inner_object->[REQ_ID];
	delete $active_request_ids{$id};

	if (_free_request_id($id)) {
		tied(%{$inner_object->[REQ_CREATE_STAGE]})->_request_context_destroy($id)
			if $inner_object->[REQ_CREATE_STAGE];
		tied(%{$inner_object->[REQ_TARGET_STAGE]})->_request_context_destroy($id)
			if $inner_object->[REQ_TARGET_STAGE];
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

sub _push {
	my ($self, $request, $stage, $method) = @_;
	push @request_stack, [
		$request,     # RS_REQUEST
		$stage,       # RS_STAGE
		$method,      # RS_METHOD
	];
}

sub _invoke {
	my ($self, $method) = @_;
	my $self_data = tied(%$self);

	DEBUG and warn(
		"\t$self invoking $self_data->[REQ_TARGET_STAGE] method $method:\n",
		"\t\tMy req  = $self_data->[REQ_TARGET_STAGE]{req}\n",
		"\t\tMy rsp  = $self_data->[REQ_TARGET_STAGE]{rsp}\n",
		"\t\tPar req = $self_data->[REQ_PARENT_REQUEST]\n",
	);

	$self_data->[REQ_TARGET_STAGE]->$method($self_data->[REQ_ARGS]);
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

	foreach my $param (qw(_stage _method)) {
		next if exists $args->{$param};
		croak "$class is missing the '$param' parameter";
	}

	# TODO - What's the "right" way to make fields inheritable without
	# clashing in Perl?

	tie my (%self), "POE::Request::TiedAttributes", [
		delete $args->{_stage},       # REQ_TARGET_STAGE
		delete $args->{_method},      # REQ_TARGET_METHOD
		{ },                          # REQ_CHILD_REQUESTS
		{ },                          # REQ_RESOURCES
		$package,                     # REQ_CREATE_PKG
		$filename,                    # REQ_CREATE_FILE
		$line,                        # REQ_CREATE_LINE
		0,                            # REQ_CREATE_STAGE
		{ },                          # REQ_ARGS
	];

	my $self = bless \%self, $class;

	return $self;
}

# Send the request to its destination.
sub _send_to_target {
	my $self = shift;
	my $self_data = tied(%$self);
	Carp::confess "whoops" unless $self_data->[REQ_TARGET_STAGE];
	$poe_kernel->post(
		$self_data->[REQ_TARGET_STAGE]->_get_session_id(), "stage_request", $self
	);
}

sub new {
	my ($class, %args) = @_;

	my $self = $class->_request_constructor(\%args);
	my $self_data = tied(%$self);

	# Gather up the type/method mapping for any responses to this
	# request.

	my %returns;
	foreach (keys %args) {
		next unless /^_on_(\S+)$/;
		$returns{$1} = delete $args{$_};
	}

	$self_data->[REQ_RETURNS] = \%returns;

	# Set the parent request to be the currently active request.
	# New request = new context.

	$self_data->[REQ_PARENT_REQUEST] = POE::Request->_get_current_request();
	$self_data->[REQ_ID] = $self->_allocate_request_id();

	# If we have a parent request, then we need to associate this new
	# request with it.  The references between parent and child requests
	# are all weak because it's up to the creator to decide when
	# destruction happens.

	if ($self_data->[REQ_PARENT_REQUEST]) {
		my $parent_data = tied(%{$self_data->[REQ_PARENT_REQUEST]});
		$self_data->[REQ_CREATE_STAGE] = $parent_data->[REQ_TARGET_STAGE];
		weaken $self_data->[REQ_CREATE_STAGE];

		$parent_data->[REQ_CHILD_REQUESTS]{$self} = $self;
		weaken $parent_data->[REQ_CHILD_REQUESTS]{$self};
	}

	DEBUG and warn(
		"$self_data->[REQ_PARENT_REQUEST] created $self:\n",
		"\tMy parent request = $self_data->[REQ_PARENT_REQUEST]\n",
		"\tDelivery request  = $self\n",
		"\tDelivery response = 0\n",
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

	my $self_data = tied(%$self);
	$self_data->[REQ_ARGS] = { %args };
}

sub init {
	# Virtual base method.  Do nothing by default.
}

# Deliver the request to its destination.  Requesting down into a
# stage, so req is the request that invoked the method, and _rsp is
# zero because there's no downward path from here.

sub deliver {
	my ($self, $method) = @_;
	my $self_data = tied(%$self);

	my $target_stage = $self_data->[REQ_TARGET_STAGE];
	my $target_stage_data = tied(%$target_stage);

	my $delivery_req = $self_data->[REQ_DELIVERY_REQ] || $self;
	$target_stage_data->[REQUEST]  = $delivery_req;
	$target_stage_data->[RESPONSE] = 0;

	my $target_method = $method || $self_data->[REQ_TARGET_METHOD];
	$self->_push($self, $target_stage, $target_method);

	$self->_invoke($target_method);

	$self->_pop($self, $target_stage, $target_method);

	my $old_rsp = delete $target_stage_data->[RESPONSE];
	my $old_req = delete $target_stage_data->[REQUEST];

#	die "bad rsp" unless $old_rsp == 0;
#	die "bad req" unless $old_req == $delivery_req;
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
	my $self_data = tied(%$self);

	# Cancel all the children first.

	foreach my $child (values %{$self_data->[REQ_CHILD_REQUESTS]}) {
		eval {
			$child->cancel();
		};
	}

	# A little sanity check.  We should have no children once they're
	# canceled.
	die "canceled parent has children left" if (
		keys %{$self_data->[REQ_CHILD_REQUESTS]}
	);

	# Disengage from our parent.
	# TODO - Use a mutator rather than grope inside the parent object.

	if ($self_data->[REQ_PARENT_REQUEST]) {
		my $parent_data = tied(%{$self_data->[REQ_PARENT_REQUEST]});
		delete $parent_data->[REQ_CHILD_REQUESTS]{$self};
		$self_data->[REQ_PARENT_REQUEST] = 0;
	}
}

sub _emit {
	my ($self, $class, %args) = @_;
	my $self_data = tied(%$self);

	# Where does the message go?
	# TODO - Have croak() reference the proper package/file/line.

	my $parent_stage = $self_data->[REQ_CREATE_STAGE];
	confess "Can't emit message: Requester is not a POE::Stage class" unless (
		$parent_stage
	);

	# Pull out the message type, and map it to a method.

	my $message_type = delete $args{_type};
	croak "Message must have a _type parameter" unless defined $message_type;
	my $message_method = (
		(exists $self_data->[REQ_RETURNS]{$message_type})
		? $self_data->[REQ_RETURNS]{$message_type}
		: "unknown_type"
	);

	# Reconstitute the parent's context.
	my $parent_context;
	my $parent_request = $self_data->[REQ_PARENT_REQUEST];
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