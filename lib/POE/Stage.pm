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

Complex programs generally perform their tasks in multiple stages.
For example, a web request is performed in four major stages: 1. Look
up the host's address.  2. Connect to the remote host.  3.  Transmit
the request.  4. Receive the response.

POE::Stage promotes the decomposition of multi-step processes into
discrete, reusable stages.  In this case: POE::Stage::Resolver will
resolve host names into addresses, POE::Stage::Connector will
establish a socket connection to the remote host, and
POE::Stage::StreamIO will transmit the request and receive the
response.

POE::Stage promotes composition of high-level stages from lower-level
ones.  POE::Stage::HTTPClient might present a simplified
request/response interface while internally creating and coordinating
more complex interaction between POE::Stage::Resolver, Connector, and
StreamIO.  This remains to be seen, however, as POE::Stage is still
very new software.

POE stages are message based.  The message classes, POE::Request and
its subclasses, implement a standard request/response interface for
POE stages.  Where possible, POE message passing attempts to mimic
simpler, more direct calling and returning, albeit asynchronously.
POE::Stage and POE::Request also implement closures which greatly
simplify asynchronous state management.

=cut

package POE::Stage;

use warnings;
use strict;

use vars qw($VERSION);
$VERSION = do {my($r)=(q$Revision$=~/(\d+)/);sprintf"0.%04d",$r};

use POE::Session;

use Attribute::Handlers;
use PadWalker qw(var_name peek_my);
use Scalar::Util qw(blessed reftype);
use Carp qw(croak);
use POE::Stage::TiedAttributes;
use Devel::LexAlias qw(lexalias);

use POE::Request::Emit;
use POE::Request::Return;
use POE::Request::Recall;
use POE::Request qw(REQ_ID);

use POE::Attribute::Request::Scalar;
use POE::Attribute::Request::Hash;
use POE::Attribute::Request::Array;

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
			eval { "POE::Watcher::Wheel::$1"->deliver(0, @_[ARG0..$#_]); };
		},
		wheel_event_1 => sub {
			$_[CALLER_FILE] =~ m{/([^/.]+)\.pm};
			eval { "POE::Watcher::Wheel::$1"->deliver(1, @_[ARG0..$#_]); };
		},
		wheel_event_2 => sub {
			$_[CALLER_FILE] =~ m{/([^/.]+)\.pm};
			eval { "POE::Watcher::Wheel::$1"->deliver(2, @_[ARG0..$#_]); };
		},
		wheel_event_3 => sub {
			$_[CALLER_FILE] =~ m{/([^/.]+)\.pm};
			eval { "POE::Watcher::Wheel::$1"->deliver(3, @_[ARG0..$#_]); };
		},
		wheel_event_4 => sub {
			$_[CALLER_FILE] =~ m{/([^/.]+)\.pm};
			eval { "POE::Watcher::Wheel::$1"->deliver(4, @_[ARG0..$#_]); };
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

This may change as POE::Stage implements L<Class::MOP>, L<Moose>, or
other Perl 6 ways.

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

=head2 Req (attribute)

Defines the Req lexical variable attribute for request closures.
Variables declared this way become members of the request the current
stage is currently handling.

	sub some_handler {
		my ($self, $args) = @_;
		my $request_field :Req = "some value";
		my $sub_request :Req = POE::Request->new(
			...,
			on_xyz => "xyz_handler"
		);
	}

Request members are intended to be used as continuations between
handlers that are invoked within the same request.  The previous
handler may eventually pass execution to xyz_handler(), which can
access $request_field and $sub_request if the current stage is still
handling the current request.

	sub xyz_handler {
		my ($self, $args) = @_;
		my $request_field :Req;
		print "$request_field\n";  # "some value"
	}

Fields may also be associated with sub-requests being made by the
current stage.  In this case, variables declared :Rsp within handlers
for responses to the associated request will also be visible.

	sub some_other_handler {
		my ($self, $args) = @_;
		my $request_field :Req = "some value";
		my $sub_request :Req = POE::Request->new(
			...,
			on_xyz => "response_handler"
		);
		my $response_field :Req($sub_request) = "visible in the response";
	}

	sub response_handler {
		my ($self, $args) = @_;
		my $request_field :Req;
		my $response_field :Rsp;
		print "$request_field\n";   # "some value"
		print "$response_field\n";  # "visible in the response";
	}

Three versions of Req() are defined: One each for scalars, arrays, and
hashes.  You needn't know this since the appropriate one will be used
depending on the type of variable declared.

=cut

{
	no warnings 'redefine';

	sub Req :ATTR(SCALAR,RAWDATA) {
		my ($pkg, $sym, $ref, $attr, $data, $phase) = @_;

		croak "can't declare a blessed variable as :Req" if blessed($ref);

		my $name = var_name(4, $ref);

		my $request;
		if (defined $data) {
			my $my = peek_my(4);
			croak "Unknown request object '$data'" unless (
				exists $my->{$data}
				and reftype($my->{$data}) eq "REF"
				and UNIVERSAL::isa(${$my->{$data}}, "POE::Request")
			);
			$request = ${$my->{$data}};
		}
		else {
			$request = POE::Request->_get_current_request();
		}

		# TODO - To make this work tidily, we should translate $name into a
		# reference to the proper request/response field and pass that into
		# the tie handler.  Then the tied variable can work directly with
		# the field, or perhaps a weak copy of it.

		return tie(
			$$ref, "POE::Attribute::Request::Scalar",
			POE::Request->_get_current_stage(),
			$request->get_id(),
			$name
		);
	}

	sub Req :ATTR(HASH,RAWDATA) {
		my ($pkg, $sym, $ref, $attr, $data, $phase) = @_;

		croak "can't declare a blessed variable as :Req" if blessed($ref);

		my $name = var_name(4, $ref);

		my $request;
		if (defined $data) {
			my $my = peek_my(4);
			croak "Unknown request object '$data'" unless (
				exists $my->{$data}
				and reftype($my->{$data}) eq "REF"
				and UNIVERSAL::isa(${$my->{$data}}, "POE::Request")
			);
			$request = ${$my->{$data}};
		}
		else {
			$request = POE::Request->_get_current_request();
		}

		# TODO - To make this work tidily, we should translate $name into a
		# reference to the proper request/response field and pass that into
		# the tie handler.  Then the tied variable can work directly with
		# the field, or perhaps a weak copy of it.

		return tie(
			%$ref, "POE::Attribute::Request::Hash",
			POE::Request->_get_current_stage(),
			$request->get_id(),
			$name
		);
	}

	sub Req :ATTR(ARRAY,RAWDATA) {
		my ($pkg, $sym, $ref, $attr, $data, $phase) = @_;

		croak "can't declare a blessed variable as :Req" if blessed($ref);

		my $name = var_name(4, $ref);

		my $request;
		if (defined $data) {
			my $my = peek_my(4);
			croak "Unknown request object '$data'" unless (
				exists $my->{$data}
				and reftype($my->{$data}) eq "REF"
				and UNIVERSAL::isa(${$my->{$data}}, "POE::Request")
			);
			$request = ${$my->{$data}};
		}
		else {
			$request = POE::Request->_get_current_request();
		}

		# TODO - To make this work tidily, we should translate $name into a
		# reference to the proper request/response field and pass that into
		# the tie handler.  Then the tied variable can work directly with
		# the field, or perhaps a weak copy of it.

		return tie(
			@$ref, "POE::Attribute::Request::Array",
			POE::Request->_get_current_stage(),
			$request->get_id(),
			$name
		);
	}

	### XXX - Experimental :Self handler.
	# Only for scalars (self reference).
	# TODO - Try to also get it working for hashes.  That is, make
	#   my %self :Self;
	# cause %self to be an alias for %$self ... somehow.

	sub Self :ATTR(SCALAR,RAWDATA) {
		my $ref = $_[2];
		croak "can't register blessed things as Self fields" if blessed($ref);

		package DB;
		my @x = caller(4);
		$$ref = $DB::args[0];
	}

	### XXX - Experimental :Arg handler.
	# TODO - Support other types?

	sub Arg :ATTR(SCALAR,RAWDATA) {
		my ($pkg, $sym, $ref, $attr, $data, $phase) = @_;
		croak "can't register blessed things as Arg fields" if blessed($ref);
		croak "can only register scalars as Arg fields" if ref($ref) ne "SCALAR";

		my $name = var_name(4, $ref);
		$name =~ s/^\$//;

		package DB;
		my @x = caller(4);
		$$ref = $DB::args[1]{$name};
	}

	### XXX - Experimental :Memb handlers.

	sub Memb :ATTR(SCALAR,RAWDATA) {
		my $ref = $_[2];
		croak "can't register blessed things as Memb fields" if blessed($ref);

		my $name = var_name(4, $ref);

		my $self;
		{
			package DB;
			my @x = caller(4);
			$self = $DB::args[0];
		}

		$self->{$name} = undef unless exists $self->{$name};
		lexalias(4, $name, \$self->{$name});
	}

	sub Memb :ATTR(ARRAY,RAWDATA) {
		my $ref = $_[2];
		croak "can't register blessed things as Memb fields" if blessed($ref);

		my $name = var_name(4, $ref);

		my $self;
		{
			package DB;
			my @x = caller(4);
			$self = $DB::args[0];
		}

		$self->{$name} = [] unless exists $self->{$name};
		lexalias(4, $name, \$self->{$name});
	}

	sub Memb :ATTR(HASH,RAWDATA) {
		my $ref = $_[2];
		croak "can't register blessed things as Memb fields" if blessed($ref);

		my $name = var_name(4, $ref);

		my $self;
		{
			package DB;
			my @x = caller(4);
			$self = $DB::args[0];
		}

		$self->{$name} = {} unless exists $self->{$name};
		lexalias(4, $name, \$self->{$name});
	}
}

{
	no warnings 'redefine';

	sub Rsp :ATTR(SCALAR,RAWDATA) {
		my ($pkg, $sym, $ref, $attr, $data, $phase) = @_;
		#warn "pkg($pkg) sym($sym) ref($ref) attr($attr) data($data) phase($phase)\n";

		croak "can't declare a blessed variable as :Rsp" if blessed($ref);

		my $name = var_name(4, $ref);

		# TODO - To make this work tidily, we should translate $name into a
		# reference to the proper request/response field and pass that into
		# the tie handler.  Then the tied variable can work directly with
		# the field, or perhaps a weak copy of it.

		my $stage = POE::Request->_get_current_stage();
		my $response_id = $stage->{rsp}->get_id();

		return tie(
			$$ref, "POE::Attribute::Request::Scalar",
			$stage,
			$response_id,
			$name
		);
	}

	sub Rsp :ATTR(HASH,RAWDATA) {
		my ($pkg, $sym, $ref, $attr, $data, $phase) = @_;
		#warn "pkg($pkg) sym($sym) ref($ref) attr($attr) data($data) phase($phase)\n";

		croak "can't declare a blessed variable as :Rsp" if blessed($ref);

		my $name = var_name(4, $ref);

		# TODO - To make this work tidily, we should translate $name into a
		# reference to the proper request/response field and pass that into
		# the tie handler.  Then the tied variable can work directly with
		# the field, or perhaps a weak copy of it.

		my $stage = POE::Request->_get_current_stage();
		my $response_id = $stage->{rsp}->get_id();

		return tie(
			%$ref, "POE::Attribute::Request::Hash",
			$stage,
			$response_id,
			$name
		);
	}

	sub Rsp :ATTR(ARRAY,RAWDATA) {
		my ($pkg, $sym, $ref, $attr, $data, $phase) = @_;
		#warn "pkg($pkg) sym($sym) ref($ref) attr($attr) data($data) phase($phase)\n";

		croak "can't declare a blessed variable as :Rsp" if blessed($ref);

		my $name = var_name(4, $ref);

		# TODO - To make this work tidily, we should translate $name into a
		# reference to the proper request/response field and pass that into
		# the tie handler.  Then the tied variable can work directly with
		# the field, or perhaps a weak copy of it.

		my $stage = POE::Request->_get_current_stage();
		my $response_id = $stage->{rsp}->get_id();

		return tie(
			@$ref, "POE::Attribute::Request::Array",
			$stage,
			$response_id,
			$name
		);
	}
}

1;

=head1 USING

TODO - Describe how POE::Stage is used.  Outline the general pattern
for designing and subclassing.

=head1 DESIGN GOALS

As mentioned before, POE::Stage strives to implement a standard for
POE best practices.  It embodies some of POE's best and most common
design patterns so you no longer have to.

Things POE::Stage does for you:

It manages POE::Session objects so you can deal with truly
object-oriented POE::Stages.  The event-based gyrations are subsumed
and automated by POE::Stage.

It provides a form of message-based continuation so that specially
declared variables (using the :Req and :Rsp attributes) are
automatically tracked between the time a message is sent and its
response arrives.  No more HEAPs and tracking request state manually.

It simplifies the call signature of message handlers, eliminating @_
list slices, positional parameters, and mysteriously imported
constants (HEAP, ARG0, etc.).

It defines a standardized message class (POE::Request and its
subclasses) and a mechanism for passing messages between POE stages.
POE::Stage authors won't need to roll their own interface mechanisms,
so programmers will not need to learn one for each module in use.

POE::Stage implements object-oriented classes for low-level event
watchers.  This simplifies POE::Kernel's interface and allows it to be
extended celanly.  Event watcher ownerships and lifetimes are clearly
indicated.

Standardize the means to shut down stages.  POE components implement a
variety of shutdown methods.  POE::Stage objects are shut down by
destroying their objects.

It simplifies cleanup when requests are finished.  The convention of
storing request-scoped data in request continuations means that
sub-stages, sub-requests, event watchers, and everything else is
automatically cleaned up when a request falls out of scope.

=head1 BUGS

See http://thirdlobe.com/projects/poe-stage/report/1 for known issues.
See http://thirdlobe.com/projects/poe-stage/newticket to report one.

=head1 SEE ALSO

POE::Request is the class that defines inter-stage messages.
POE::Watcher is the base class for event watchers, without which
POE::Stage won't run very well.

L<http://thirdlobe.com/projects/poe-stage/> - POE::Stage is hosted
here.

L<http://www.eecs.harvard.edu/~mdw/proj/seda/> - SEDA, the Staged
Event Driven Architecture.  It's Java, though.

=head1 AUTHORS

Rocco Caputo <rcaputo@cpan.org>.

=head1 LICENSE

POE::Stage is Copyright 2005-2006 by Rocco Caputo.  All rights are
reserved.  You may use, modify, and/or distribute this module under
the same terms as Perl itself.

=cut
