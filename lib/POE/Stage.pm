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

POE::Stage is a proposed base class for POE components.  It implements
some of the most common design patterns that have arisen during
several years of POE::Component development.

Complex programs generally perform their tasks in multiple stages.
For example, a web request is performed in four distinct stages: 1.
Look up the host's address.  2. Connect to the remote host.  3.
Transmit the request.  4. Receive the response.

By design, POE::Stage promotes the decomposition of multi-step
processes into discrete, reusable stages.  We might break our HTTP
client into three POE::Stage objects: POE::Stage::Resolver, to resolve
host names into addresses; POE::Stage::Connector to establish a socket
connection to the remote host; and POE::Stage::StreamIO to transmit
the request and receive the response.

POE::Stage promotes composition of high-level stages from lower-level
ones.  In our hypothetical situation, POE::Stage::HTTPClient might
present a simplified request/response interface while internally
creating the previous stages and coordinating their interaction.  This
remains to be seen, however, as POE::Stage is still very new software.

POE stages are message based.  The message classes, POE::Request and
its subclasses, implement a standard request/response interface.
Where possible, POE message passing attempts to mimic simpler, more
direct calling and returning, albeit asynchronously.  POE::Stage and
POE::Request also implement a form of closures that simplifies state
management between requests and responses.

=cut

package POE::Stage;

use warnings;
use strict;

use vars qw($VERSION);
$VERSION = '0.01_00';

use POE::Session;

use Attribute::Handlers;
use PadWalker qw(var_name peek_my peek_sub);
use Scalar::Util qw(blessed reftype);
use Carp qw(croak);
use POE::Stage::TiedAttributes;
use Devel::LexAlias qw(lexalias);

use POE::Request::Emit;
use POE::Request::Return;
use POE::Request::Recall;
use POE::Request qw(REQ_ID);

sub import {
	my $class = shift;
	my $caller = caller();

	foreach my $export (@_) {
		no strict 'refs';

		if ($export eq ":base") {
			unshift @{ $caller . "::ISA" }, $class;
			next;
		}

		*{ $caller . "::$export" } = *{ $class . "::$export" };
	}
}

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
			eval { $resource->[0]->deliver(); };
			die if $@;
		},

		# Handle an I/O event.  Deliver it to its resource.
		# $resource is an envelope around a weak POE::Watcher reference.
		stage_io => sub {
			my $resource = $_[ARG2];
			eval { $resource->[0]->deliver(); };
			die if $@;
		},

		# Deliver to wheels based on the wheel ID.  Different wheels pass
		# their IDs in different ARGn offsets, so we need a few of these.
		wheel_event_0 => sub {
			$_[CALLER_FILE] =~ m{/([^/.]+)\.pm};
			eval { "POE::Watcher::Wheel::$1"->deliver(0, @_[ARG0..$#_]); };
			die if $@;
		},
		wheel_event_1 => sub {
			$_[CALLER_FILE] =~ m{/([^/.]+)\.pm};
			eval { "POE::Watcher::Wheel::$1"->deliver(1, @_[ARG0..$#_]); };
			die if $@;
		},
		wheel_event_2 => sub {
			$_[CALLER_FILE] =~ m{/([^/.]+)\.pm};
			eval { "POE::Watcher::Wheel::$1"->deliver(2, @_[ARG0..$#_]); };
			die if $@;
		},
		wheel_event_3 => sub {
			$_[CALLER_FILE] =~ m{/([^/.]+)\.pm};
			eval { "POE::Watcher::Wheel::$1"->deliver(3, @_[ARG0..$#_]); };
			die if $@;
		},
		wheel_event_4 => sub {
			$_[CALLER_FILE] =~ m{/([^/.]+)\.pm};
			eval { "POE::Watcher::Wheel::$1"->deliver(4, @_[ARG0..$#_]); };
			die if $@;
		},
	},
)->ID();

sub _get_session_id {
	return $singleton_session_id;
}

=head1 RESERVED METHODS

As a base class, POE::Stage must reserve a small number of methods for
its own.

=head2 new ARGEMENT_PAIRS

Create and return a new POE::Stage object, optionally passing
name/value ARGUMENT_PAIRS to the new stage's init() callback.  See the
description of init() for more details.

Unlike in POE, you must save the object POE::Stage->new() returns if
you intend for it to live.

It is not recommended that subclasses override new.  Rather, they
should implement init() callbacks to initialize themselves after
creation.

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
	# req() is undef.  That's probably good.
	# rsp() is also undef.  That's also good.
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

=head2 init ARGUMENT_PAIRS

init() is a virtual base method used to initialize POE::Stage objects
after construction.  Subclasses override this to perform their own
initialization.  The new() constructor will pass its public parameters
through to $self->init($name_value_pairs).  They will also be available
as $arg_name lexicals:

	sub init {
		my $arg_foo;  # contains the "foo" argument
	}

=cut

sub init {
	# Do nothing.  Don't even throw an error.
}

# TODO - Make these internal?  Possibly part of the tied() interface?

sub self {
	package DB;
	my @x = caller(1);
	return $DB::args[0];
}

sub req {
	my $stage = tied(%{POE::Request->_get_current_stage()});
	return $stage->_get_request();
}

sub rsp {
	my $stage = tied(%{POE::Request->_get_current_stage()});
	return $stage->_get_response();
}

=head2 Handler

Handler implements an attribute that defines which subs are message
handlers.  Only message handlers have lexical magic.

	sub some_method :Handler {
		# Lexical magic occurs here.
	}

	sub not_a_handler {
		# No lexical magic.
	}

=cut

sub Handler :ATTR(CODE) {
	my ($pkg, $sym, $ref, $attr, $data, $phase) = @_;

	no strict 'refs';
	no warnings 'redefine';

	my $sub_name = *{$sym}{NAME};

	# FIXME - Appropriate carplevel.
	# FIXME - Allow anonymous handlers?
	unless (defined $sub_name) {
		croak "Anonymous handler not yet supported";
	}

	*{$pkg . "::" . $sub_name} = sub {

		# Cache these for speed.
		my ($self, $tied_self, $arg, $req, $rsp);

		my $pad = peek_sub($ref);
		while (my ($var_name, $var_reference) = each %$pad) {

			if ($var_name eq '$self') {
				$self = self() unless defined $self;
				lexalias($ref, $var_name, \$self);
				next;
			}

			if ($var_name eq '$req') {
				unless (defined $req) {
					unless (defined $tied_self) {
						$self = self() unless defined $self;
						$tied_self = tied(%$self);
					}
					$req = $tied_self->_get_request();
				}

				lexalias($ref, $var_name, \$req);
				next;
			}

			if ($var_name eq '$rsp') {
				unless (defined $rsp) {
					unless (defined $tied_self) {
						$self = self() unless defined $self;
						$tied_self = tied(%$self);
					}
					$rsp = $tied_self->_get_response();
				}

				lexalias($ref, $var_name, \$rsp);
				next;
			}

			next unless $var_name =~ /^([\$\@\%])(req|rsp|arg|self)_(\S+)/;

			my ($sigil, $prefix, $base_member_name) = ($1, $2, $3);
			my $member_name = $sigil . $base_member_name;

			# Determine which object to use based on the prefix.

			my $obj;
			if ($prefix eq 'req') {
				$req = POE::Request->_get_current_request() unless defined $req;

				unless (defined $tied_self) {
					$self = self() unless defined $self;
					$tied_self = tied(%$self);
				}

				# Get the existing member reference.

				my $member_ref = $tied_self->_request_context_fetch(
					$req->get_id(),
					$member_name,
				);

				# Autovivify if necessary.

				unless (defined $member_ref) {
					if ($sigil eq '$') {
						my $new_scalar;
						$member_ref = \$new_scalar;
					}
					elsif ($sigil eq '@') {
						$member_ref = [];
					}
					elsif ($sigil eq '%') {
						$member_ref = {};
					}

					$tied_self->_request_context_store(
						$req->get_id(),
						$member_name,
						$member_ref,
					);
				}

				# Alias the member.

				lexalias($ref, $var_name, $member_ref);
				next;
			}

			if ($prefix eq 'rsp') {
				unless (defined $rsp) {
					unless (defined $tied_self) {
						$self = self() unless defined $self;
						$tied_self = tied(%$self);
					}
					$rsp = $tied_self->_get_response();
				}

				# Get the existing member reference.

				my $member_ref = $tied_self->_request_context_fetch(
					$rsp->get_id(),
					$member_name,
				);

				# Autovivify if necessary.

				unless (defined $member_ref) {
					if ($sigil eq '$') {
						my $new_scalar;
						$member_ref = \$new_scalar;
					}
					elsif ($sigil eq '@') {
						$member_ref = [];
					}
					elsif ($sigil eq '%') {
						$member_ref = {};
					}

					$tied_self->_request_context_store(
						$rsp->get_id(),
						$member_name,
						$member_ref,
					);
				}

				lexalias($ref, $var_name, $member_ref);
				next;
			}

			if ($prefix eq 'arg') {
				unless (defined $arg) {
					package DB;
					my @x = caller(0);
					$arg = $DB::args[1];
				}

				if ($sigil eq '$') {
					$$var_reference = $arg->{$base_member_name};
					next;
				}

				if ($sigil eq '@') {
					@$var_reference = @{$arg->{$base_member_name}};
					next;
				}

				if ($sigil eq '%') {
					%$var_reference = %{$arg->{$base_member_name}};
					next;
				}
			}

			if ($prefix eq 'self') {
				unless (defined $tied_self) {
					$self = self() unless defined $self;
					$tied_self = tied(%$self);
				}

				# Get the existing member reference.

				my $member_ref = $tied_self->_self_fetch($member_name);

				# Autovivify if necessary.

				unless (defined $member_ref) {
					if ($sigil eq '$') {
						my $new_scalar;
						$member_ref = \$new_scalar;
					}
					elsif ($sigil eq '@') {
						$member_ref = [];
					}
					elsif ($sigil eq '%') {
						$member_ref = {};
					}

					$tied_self->_self_store($member_name, $member_ref);
				}

				# Alias the member.

				lexalias($ref, $var_name, $member_ref);

				next;
			}
		}

		goto $ref;
	};
}

=head2 expose OBJECT, LEXICAL [, LEXICAL[, LEXICAL ...]]

The expose function, which must be imported explicitly, allows your
handlers to expose members of a specific request or response OBJECT.
Each member will be exposed as a particular LEXICAL variable.

To set a magic cookie on a sub-request:

	sub do_request :Handler {
		my $req_subrequest = POE::Request->new( ... );
		expose $req_subrequest, my $sub_cookie;
		$sub_cookie = "stored in the subrequest";
	}

OBJECT must be a subclass of POE::Request.

=cut

sub expose ($\[$@%];\[$@%]\[$@%]\[$@%]\[$@%]\[$@%]\[$@%]\[$@%]\[$@%]\[$@%]\[$@%]\[$@%]\[$@%]\[$@%]\[$@%]\[$@%]\[$@%]\[$@%]\[$@%]\[$@%]\[$@%\[$@%\[$@%]]]\[$@%]) {
	my $request = shift;

	# Validate that we're exposing a member of a POE::Request object.

	croak "Unknown request object '$request'" unless (
		UNIVERSAL::isa($request, "POE::Request")
	);

	# Translate prefixed lexicals into POE::Request member names.  Alias
	# the members to the lexicals, creating new members as necessary.

	for (my $i = 0; $i < @_; $i++) {
		my $var_reference = $_[$i];
		my $var_name = var_name(1, $var_reference);

		unless ($var_name =~ /^([\$\@\%])([^_]+)_(\S+)/) {
			croak "'$var_name' is an illegal lexical name";
		}

		my ($sigil, $prefix, $base_member_name) = ($1, $2, $3);
		my $member_name = $sigil . $base_member_name;

		# Some prefixes fail.
		croak "can't expose $var_name" if $prefix =~ /^(arg|req|rsp|self)$/;

		my $stage = tied(%{POE::Request->_get_current_stage()});
		my $member_ref = $stage->_request_context_fetch(
			$request->get_id(),
			$member_name,
		);

		# Autovivify a new member.

		unless (defined $member_ref) {
			if ($sigil eq '$') {
				# Because I'm afraid to say $scalar = \$scalar.
				my $new_scalar = undef;
				$stage->_request_context_store(
					$request->get_id(),
					$member_name,
					$member_ref = \$new_scalar,
				);
			}
			elsif ($sigil eq '@') {
				$stage->_request_context_store(
					$request->get_id(),
					$member_name,
					$member_ref = [],
				);
			}
			elsif ($sigil eq '%') {
				$stage->_request_context_store(
					$request->get_id(),
					$member_name,
					$member_ref = {},
				);
			}
			else {
				croak "'$var_name' has an odd sigil";
			}
		}

		# Alias that puppy.

		lexalias(1, $var_name, $member_ref);
	}
}

1;

=head1 USING

TODO - Describe how POE::Stage is used.  Outline the general pattern
for designing and subclassing.

=head1 DESIGN GOALS

As mentioned before, POE::Stage is a stab at defining some best
practices for POE as a base class for POE components.  It implements
some of POE's best and most common design patterns so you no longer
have to.  As a side effect, it implements them in a single, standard
way.

POE::Stage hides POE::Session and the need to explicitly define
subroutines and events in separate places.  The Handler subroutine
attribute defines which methods handle messages:

	sub handle_foo :Handler {
		...
	}

POE::Stage simplifies message passing and response handling in at
least three ways.  Consider:

	my $request = POE::Request->new(
		stage => $target_stage,
		method => $target_method,
		args => \%arguments,
		on_response_x => "handler_x",
		on_response_y => "handler_y",
		on_response_z => "handler_z",
	);

First, it provides standard message clasess.  Developers don't need to
roll their own, probably non-interoperable messaging scheme.  The
named \%arguments are supplied and are available to each handler in a
standard way, which is described in the MAGICAL LEXICAL TOUR.

Second, POE::Stage provides request-scoped closures via $req_foo,
$rsp_foo, and expose().  Stages use these mechanisms to save and
access data in specific request and response contexts, eliminating the
need to do it explicitly within HEAPs.

Third, response destinations are tied to the requests themselves.  In
the above example, responses of type "response_x" will be handled by
"handler_x".  The logic flow of a complex program is more readily
apparent.

The mechanisms of message passing and context management become
implicit, allowing them to be extended transparently.  It's hoped that
interprocess communication can be added without exposing too much work
to developers.

POE::Stage includes object-oriented classes for low-level event
watchers.  They simplify and standardize POE::Kernel's interface, and
they allow it to be extended cleanly through normal OO techniques.
The lifespans of each resource are tightly coupled to the lifespans of
their watcher objects, so ownership and relevance are clearly
indicated.

POE::Stage standardizes shutdown semantics for requests and stages.
Requests are canceled by destroying their objects, and stages are shut
down the same way.

POE::Stage simplifies cascaded cleanup for requests and stages.
Resources for a particular request are stored within that request's
scope.  Canceling the request destroys that scope, and all the
resources contained within it.  If those resources include other
stages, they too are canceled, and so on.

=head1 MAGICAL LEXICAL TOUR

POE::Stage uses lexical aliasing to expose state data including
handler parameters, message-scoped values, and the current POE::Stage
object and other values.  The technique has been abstracted into
another module, Lexical::Persistence.

Certain lexical variables have special meanings within methods with
the :Handler attribute:

	sub foo :Handler {
		my ($arg_one, $arg_two, $arg_three);
		my $self;
		my $req;
		my $rsp;
		my $req_member;
		my $rsp_member;
		my $self_member;
	}

Variable prefixes figure heavily in POE::Stage handlers.  In the above
example, the prefixes are "arg_", "req_", "rsp_" and "self_".  Each
corresponds to a different data scope: named arguments, the request
currently being handled, a response currently being accepted, or the
POE::Stage object itself.

The unprefixed $self, $req, and $rsp lexicals refer to objects: The
current POE::Stage, the current request, or the current response.

See Lexical::Persistence for details about the techniques being used
here.

=head1 BUGS

See http://thirdlobe.com/projects/poe-stage/report/1 for known issues.
See http://thirdlobe.com/projects/poe-stage/newticket to report one.

POE::Stage is too young for production use.  For example, its syntax
is still changing.  You probably know what you don't like, or what you
need that isn't included, so consider fixing or adding that, or at
least discussing it with the people on POE's mailing list or IRC
channel.  Your feedback and contributions will bring POE::Stage closer
to usability.  We appreciate it.

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
