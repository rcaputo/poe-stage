# $Id$

=head1 NAME

POE::Stage - a proposed base class for formalized POE components

=head1 SYNOPSIS

	# Note, this is not a complete program.
	# See the distribution's examples directory.

	my $stage = POE::Stage::Subclass->new();

	my $request = POE::Request->new(
		stage   => $stage,            # Invoke this stage
		method  => "method_name",     # calling this method
		args    => \%parameter_pairs, # with these parameters.
	);

=head1 DESCRIPTION

POE::Stage is a proposed base class for POE components.  Its purpose
is to standardize the most common design patterns that have arisen
through years of POE::Component development.

Complex programs generally perform their tasks in multiple steps, or
stages.  For example, fetching a web page requires four or so steps:
1. Look up the host's address.  2. Connect to the remote host.  3.
Transmit the request.  4. Receive the response.

POE::Stage promotes the decomposition of multi-step processes into
discrete, reusable stages.  In this case: POE::Stage::Resolver to
resolve host names into addresses.  POE::Stage::Connector to establish
a socket connection to the remote host.  POE::Stage::StreamIO to
transmit the request and receive the response.

Stages perform their tasks in response to request messages.  They
return messages containing the result of each task as it's completed.

If done right, high-level stages will be built from lower-level ones.
POE::Stage::HTTPClient would present a simple request/response
interface while internally creating and coordinating
POE::Stage::Resolver, POE::Stage::Connector, and POE::Stage::StreamIO
as necessary.

=cut

package POE::Stage;

use warnings;
use strict;

use vars qw($VERSION);
$VERSION = do {my($r)=(q$Revision$=~/(\d+)/);sprintf"0.%04d",$r};

use POE::Session;

use Scalar::Util qw(blessed);
use Carp qw(croak);
use POE::Stage::TiedAttributes;

use POE::Request::Emit;
use POE::Request::Return;
use POE::Request::Recall;
use POE::Request;

# An internal singleton POE::Session that will drive all the stages
# for the application.  This should be structured such that we can
# create multiple stages later, each driving some smaller part of the
# program.

my $singleton_session_id = POE::Session->create(
	inline_states => {
		_start => sub {
			$_[KERNEL]->alias_set(__PACKAGE__);
		},

		# Handle a request.  Map the request to a stage object/method
		# call.
		stage_request => sub {
			my $request = $_[ARG0];
			$request->deliver();
		},

		# Handle a timer.  Deliver it to its resource.
		# $resource is an envelope around a weak POE::Watcher reference.
		stage_timer => sub {
			my $resource = $_[ARG0];
			eval {
				$resource->[0]->deliver();
			};
		},

		# Handle an I/O event.  Deliver it to its resource.
		# $resource is an envelope around a weak POE::Watcher reference.
		stage_io => sub {
			my $resource = $_[ARG2];
			eval {
				$resource->[0]->deliver();
			};
		},

		# Deliver to wheels based on the wheel ID.  Different wheels pass
		# their IDs in different ARGn offsets, so we need a few of these.
		wheel_event_0 => sub {
			$_[CALLER_FILE] =~ m{/([^/.]+)\.pm};
			"POE::Watcher::Wheel::$1"->deliver(0, @_[ARG0..$#_]);
		},
		wheel_event_1 => sub {
			$_[CALLER_FILE] =~ m{/([^/.]+)\.pm};
			"POE::Watcher::Wheel::$1"->deliver(1, @_[ARG0..$#_]);
		},
		wheel_event_2 => sub {
			$_[CALLER_FILE] =~ m{/([^/.]+)\.pm};
			"POE::Watcher::Wheel::$1"->deliver(2, @_[ARG0..$#_]);
		},
		wheel_event_3 => sub {
			$_[CALLER_FILE] =~ m{/([^/.]+)\.pm};
			"POE::Watcher::Wheel::$1"->deliver(3, @_[ARG0..$#_]);
		},
		wheel_event_4 => sub {
			$_[CALLER_FILE] =~ m{/([^/.]+)\.pm};
			"POE::Watcher::Wheel::$1"->deliver(4, @_[ARG0..$#_]);
		},
	},
)->ID();

sub _get_session_id {
	return $singleton_session_id;
}

=head1 RESERVED METHODS

As a base class, POE::Stage must reserve a small number of methods for
its own.

=head2 new PARAMETER_PAIRS

Create and return a new POE::Stage object, optionally passing
key/value PAIRS in its init() callback's $args parameter.  Unlike in
POE, you must save the object POE::Stage->new() returns if you intend
to use it.

It is not recommended that subclasses override new.  Rather, they
should implement init() to initialize themselves after instantiation.

=cut

sub new {
	my $class = shift;
	croak "$class->new(...) requires an even number of parameters" if @_ % 2;

	my %args = @_;

	tie my (%self), "POE::Stage::TiedAttributes";
	my $self = bless \%self, $class;

	# TODO - Right here.  We want init() to be able to start a request
	# on behalf of the creator, but the request should be
	# self-referential.  So what should the context of init() be like?
	#
	# I think the current stage should be $self here.
	# $self->{req} is undef.  That's probably good.
	# $self->{rsp} is also undef.  That's also good.
	#
	# We should be able to store the internal request in $self.  Let's
	# try that.  To do it, though, we'll need to break POE::Request
	# encapsulation a little bit.

#	POE::Request->_push( 0, $self, "init" );

## Not used yet, but I typed it.
#	my $req = POE::Request->new(
#		_stage  => $self,
#		_method => "init",
#	);

	$self->init(\%args);

#	POE::Request->_pop( 0, $self, "init" );

	return $self;
}

=head2 init PARAMETER_PAIRS

init() is a virtual base method used to initialize POE::Stage objects
after construction.  Subclasses override this to perform their own
initialization.  The new() constructor will pass its public parameters
through to $self->init($key_value_pairs).

=cut

sub init {
	# Do nothing.  Don't even throw an error.
}

1;

=head1 USING

TODO - Describe how POE::Stage is used.  Outline the general pattern
for designing and subclassing.

=head1 DESIGN GOALS

Eliminate the need to manage POE::Session objects directly.  One
common component pattern uses an object as its command interface.
Creating the object starts an internal POE::Session.  Destroying the
command object shuts that session down.  POE::Stage takes care of the
session management.

Standardize messages between components.  POE components sport a wide
variety of message-based interfaces, limiting their interoperability.
POE::Stage provides a base POE::Message class that can be used by
itself or subclassed.

Create a class library for event watchers.  POE's Kernel-based
watchers divert their ownership away from objects and sessions.
POE::Watcher objects wrap and manage POE::Kernel's watchers, providing
a clear indicator of their ownership and lifetimes.

Eliminate positional event parameters.  POE promotes the use of
positional parameters (ARG0, ARG1, etc.)  POE::Stage uses named
parameters throughout.  POE::Watcher objects translate POE::Kernel's
ARG0-based values into named parameters.  POE::Message objects use
named parameters.

Standardize message and event handlers' calling conventions.  All
POE::Message and POE::Watcher callbacks accept the same two
parameters: $self and a hash reference containing named parameters.

Eliminate the need to manage task-specific data.  POE components must
explicitly create task contexts internally and associate them with
requests.  As requests finish, components need to ensure their
associated contexts are cleaned up or memory leaks ensue.  POE::Stage
provides special data members, $self->{req} and $self->{rsp}.  They
are automatically associated with requests being made of an outer
stage or being made to an inner or sub-stage, respectively.  They are
automatically cleaned up when a request is finished.

Standardize the means to shut down stages.  POE components implement a
variety of shutdown methods.  POE::Stage objects are shut down by
destroying their objects.

Associate high-level requests with the lower-level requests that are
made to complete a task.  Interactions between multiple POE components
requires very careful state and object management, often explicitly
coded by the components' user.  POE::Stage combines request-scoped
data with object-based requests, watchers, and stages, to
automatically clean up all the resources associated with a request.

=head1 BUGS

See http://thirdlobe.com/projects/poe-stage/report/1 for known issues.
See http://thirdlobe.com/projects/poe-stage/newticket to report one.

=head1 SEE ALSO

POE::Request is the class that defines inter-stage messages.
POE::Watcher is the base class for event watchers, without which
POE::Stage won't run very well.

L<http://thirdlobe.com/projects/poe-stage/> - POE::Stage is hosted
here.

L<http://www.eecs.harvard.edu/~mdw/proj/seda/> - SEDA.

=head1 AUTHORS

Rocco Caputo <rcaputo@cpan.org>.

=head1 LICENSE

POE::Stage is Copyright 2005 by Rocco Caputo.  All rights are
reserved.  You may use, modify, and/or distribute this module under
the same terms as Perl itself.

=cut
