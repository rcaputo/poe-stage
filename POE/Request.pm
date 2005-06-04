# $Id$

package POE::Request;

use warnings;
use strict;

use Carp qw(croak confess);
use POE::Kernel;
use Scalar::Util qw(weaken);
use POE::Request::Return;
use POE::Request::Emit;
use POE::Request::Recall;

use constant DEBUG => 0;

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
		"\t$self invoking $self->{_target_stage} method $method:\n",
		"\t\tMy _req = $self->{_target_stage}{_req}\n",
		"\t\tMy _rsp = $self->{_target_stage}{_rsp}\n",
		"\t\tPar req = $self->{_parent_request}\n",
		"\t\tContext = $self->{_context}\n",
	);

	$self->{_target_stage}->$method($self->{_args});
}

sub _pop {
	my ($self, $request) = @_;
	confess "not defined?!" unless defined $request;
	my $pop = pop @request_stack;
	confess "bad pop($pop) not request($request)" unless $pop == $request;
}

sub _get_context {
	return shift()->{_context};
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

	my $self = bless {
		_target_stage   => delete $args->{_stage},  # Stage to be invoked.
		_target_method  => delete $args->{_method}, # Method to invoke.
		_child_requests => { },         # Requests begotten from this one.
		_resources      => { },         # Resources created in this request.
		_create_pkg     => $package,    # Debugging.
		_create_fil     => $filename,
		_create_lin     => $line,
		_create_stage   => 0,
		_args           => { },         # For passing down.
	}, $class;

	return $self;
}

# Send the request to its destination.
sub _send_to_target {
	my $self = shift;
	Carp::confess "whoops" unless $self->{_target_stage};
	$poe_kernel->post(
		$self->{_target_stage}->_get_session_id(), "stage_request", $self
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
	$self->{_returns} = \%returns;

	# Set the parent request to be the currently active request.
	# New request = new context.

	$self->{_parent_request} = POE::Request->_get_current_request();
	$self->{_context} = { };

	# If we have a parent request, then we need to associate this new
	# request with it.  The references between parent and child requests
	# are all weak because it's up to the creator to decide when
	# destruction happens.

	if ($self->{_parent_request}) {
		$self->{_create_stage} = $self->{_parent_request}{_target_stage};
		weaken $self->{_create_stage};

		$self->{_parent_request}{_child_requests}{$self} = $self;
		weaken $self->{_parent_request}{_child_requests}{$self};
	}

	DEBUG and warn(
		"$self->{_parent_request} created $self:\n",
		"\tMy parent request = $self->{_parent_request}\n",
		"\tDelivery request  = $self\n",
		"\tDelivery response = 0\n",
		"\tDelivery context  = $self->{_context}\n",
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

	$self->{_args} = { %args };
}

sub init {
	# Virtual base method.  Do nothing by default.
}

# Deliver the request to its destination.  Requesting down into a
# stage, so _req is the request that invoked the method, and _rsp is
# zero because there's no downward path from here.

sub deliver {
	my ($self, $method) = @_;

	$self->_push($self);

	$self->{_target_stage}{_req} = $self;
	$self->{_target_stage}{_rsp} = 0;

	$self->_invoke($method || $self->{_target_method});

	my $old_rsp = delete $self->{_target_stage}{_rsp};
	my $old_req = delete $self->{_target_stage}{_req};

	die "bad _rsp" unless $old_rsp == 0;
	die "bad _req" unless $old_req == $self;

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

	foreach my $child (values %{$self->{_child_requests}}) {
		eval {
			$child->cancel();
		};
	}

	# A little sanity check.  We should have no children once they're
	# canceled.
	die "canceled parent has children left" if keys %{$self->{_child_requests}};

	# Disengage from our parent.
	# TODO - Use a mutator rather than grope inside the parent object.

	if ($self->{_parent_request}) {
		delete $self->{_parent_request}{_child_requests}{$self};
		$self->{_parent_request} = 0;
	}
}

sub _emit {
	my ($self, $class, %args) = @_;

	# Where does the message go?
	# TODO - Have croak() reference the proper package/file/line.

	my $parent_stage = $self->{_create_stage};
	confess "Can't emit message: Requester is not a POE::Stage class" unless (
		$parent_stage
	);

	# Pull out the message type, and map it to a method.

	my $message_type = delete $args{_type};
	croak "Message must have a _type parameter" unless defined $message_type;
	my $message_method = (
		(exists $self->{_returns}{$message_type})
		? $self->{_returns}{$message_type}
		: "unknown_type"
	);

	# Reconstitute the parent's context.
	my $parent_context;
	my $parent_request = $self->{_parent_request};
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
