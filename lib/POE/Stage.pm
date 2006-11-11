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

TODO - This documentation is out of date.

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

=head2 init PARAMETER_PAIRS

init() is a virtual base method used to initialize POE::Stage objects
after construction.  Subclasses override this to perform their own
initialization.  The new() constructor will pass its public parameters
through to $self->init($key_value_pairs).

=cut

sub init {
	# Do nothing.  Don't even throw an error.
}

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
hashes.  You need not know this since the appropriate one will be used
depending on the type of variable declared.

=cut

{
	sub Handler :ATTR(CODE) {
		my ($pkg, $sym, $ref, $attr, $data, $phase) = @_;

		# Named handler.

		{
			no strict 'refs';
			no warnings 'redefine';

			foreach my $symbol (keys %{$pkg."::"}) {
				next unless defined(my $sym_coderef = *{$pkg."::".$symbol}{CODE});
				next unless $sym_coderef == $ref;
				*{$pkg."::".$symbol} = sub {

					my $pad = peek_sub($ref);
					while (my ($var_name, $var_reference) = each %$pad) {

						# Cache these.
						my ($self, $tied_self, $arg, $req, $rsp);

						if ($var_name eq '$self') {
							unless (defined $self) {
								package DB;
								my @x = caller(0);
								$self = $DB::args[0];
							}

							lexalias($ref, $var_name, \$self);
							next;
						}

						if ($var_name eq '$req') {
							unless (defined $req) {
								unless (defined $tied_self) {
									unless (defined $self) {
										package DB;
										my @x = caller(0);
										$self = $DB::args[0];
									}
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
									unless (defined $self) {
										package DB;
										my @x = caller(0);
										$self = $DB::args[0];
									}
									$tied_self = tied(%$self);
								}
								$rsp = $tied_self->_get_response();
							}

							lexalias($ref, $var_name, \$rsp);
							next;
						}

						unless ($var_name =~ /^([\$\@\%])(req|rsp|arg|self)_(\S+)/) {
							next;
						}

						my ($sigil, $prefix, $base_member_name) = ($1, $2, $3);
						my $member_name = $sigil . $base_member_name;

						# Determine which object to use based on the prefix.

						my $obj;
						if ($prefix eq 'req') {
							$req ||= POE::Request->_get_current_request();

							unless (defined $tied_self) {
								unless (defined $self) {
									package DB;
									my @x = caller(0);
									$self = $DB::args[0];
								}
								$tied_self = tied(%$self);
							}

							if ($sigil eq '$') {
								my $scalar_ref = $tied_self->_request_context_fetch(
									$req->get_id(),
									$member_name,
								);

								unless (defined $scalar_ref) {
									my $new_scalar;
									$tied_self->_request_context_store(
										$req->get_id(),
										$member_name,
										$scalar_ref = \$new_scalar,
									);
								}

								lexalias($ref, $var_name, $scalar_ref);
								next;
							}

							if ($sigil eq '@') {
								my $array_ref = $tied_self->_request_context_fetch(
									$req->get_id(),
									$member_name,
								);

								unless (defined $array_ref) {
									$tied_self->_request_context_store(
										$req->get_id(),
										$member_name,
										$array_ref = [],
									);
								}

								lexalias($ref, $var_name, $array_ref);
								next;
							}

							if ($sigil eq '%') {
								my $hash_ref = $tied_self->_request_context_fetch(
									$req->get_id(),
									$member_name,
								);

								unless (defined $hash_ref) {
									$tied_self->_request_context_store(
										$req->get_id(),
										$member_name,
										$hash_ref = {},
									);
								}

								lexalias($ref, $var_name, $hash_ref);
								next;
							}

							die;
						}

						if ($prefix eq 'rsp') {
							unless (defined $tied_self) {
								unless (defined $self) {
									package DB;
									my @x = caller(0);
									$self = $DB::args[0];
								}
								$tied_self = tied(%$self);
							}

							$rsp ||= $tied_self->_get_response();

							if ($sigil eq '$') {
								my $scalar_ref = $tied_self->_request_context_fetch(
									$rsp->get_id(),
									$member_name,
								);

								unless (defined $scalar_ref) {
									my $new_scalar;
									$scalar_ref = \$new_scalar;
									$tied_self->_request_context_store(
										$rsp->get_id(),
										$member_name,
										$scalar_ref,
									);
								}

								lexalias($ref, $var_name, $scalar_ref);
								next;
							}

							if ($sigil eq '@') {
								my $array_ref = $tied_self->_request_context_fetch(
									$rsp->get_id(),
									$member_name,
								);

								unless (defined $array_ref) {
									$tied_self->_request_context_store(
										$rsp->get_id(),
										$member_name,
										[],
									);
								}

								lexalias($ref, $var_name, $array_ref);
								next;
							}

							if ($sigil eq '%') {
								my $hash_ref = $tied_self->_request_context_fetch(
									$rsp->get_id(),
									$member_name,
								);

								unless (defined $hash_ref) {
									$tied_self->_request_context_store(
										$rsp->get_id(),
										$member_name,
										{},
									);
								}

								lexalias($ref, $var_name, $hash_ref);
								next;
							}

							die;
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
								unless (defined $self) {
									package DB;
									my @x = caller(0);
									$self = $DB::args[0];
								}
								$tied_self = tied(%$self);
							}

							# Autovivify a member.

							unless ($tied_self->_self_exists($member_name)) {
								if ($sigil eq '$') {
									$tied_self->_self_store($member_name, $var_reference);
								}
								elsif ($sigil eq '@') {
									$tied_self->_self_store($member_name, $var_reference);
								}
								elsif ($sigil eq '%') {
									$tied_self->_self_store($member_name, $var_reference);
								}
							}

							unless ($tied_self->_self_exists($member_name)) {
								croak "POE::Stage member $member_name doesn't exist";
							}

							lexalias($ref, $var_name, $tied_self->_self_fetch($member_name));

							next;
						}

						croak "'$var_name' has an unhandled prefix";
					}

					goto $ref;
				};

				return;
			}
		}

		# FIXME - Appropriate carplevel.
		croak "Anonymous handler not yet supported";
	}

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
}

#{
#	no warnings 'redefine';
#
#	sub Req :ATTR(SCALAR,RAWDATA) {
#		my ($pkg, $sym, $ref, $attr, $data, $phase) = @_;
#
#		croak "can't declare a blessed variable as :Req" if blessed($ref);
#
#		my $name = var_name(4, $ref);
#
#		my $request;
#		if (defined $data) {
#			my $my = peek_my(4);
#			croak "Unknown request object '$data'" unless (
#				exists $my->{$data}
#				and reftype($my->{$data}) eq "REF"
#				and UNIVERSAL::isa(${$my->{$data}}, "POE::Request")
#			);
#			$request = ${$my->{$data}};
#		}
#		else {
#			$request = POE::Request->_get_current_request();
#		}
#
#		# Alias the attributed lexical variable with the appropriate
#		# request member.
#
#		my $stage = tied(%{POE::Request->_get_current_stage()});
#		my $scalar = $stage->_request_context_fetch($request->get_id(), $name);
#		unless (defined $scalar) {
#			# Because I'm afraid to say $scalar = \$scalar.
#			my $new_scalar = undef;
#			$scalar = \$new_scalar;
#			$stage->_request_context_store($request->get_id(), $name, $scalar);
#		}
#
#		lexalias(4, $name, $scalar);
#	}
#
#	sub Req :ATTR(HASH,RAWDATA) {
#		my ($pkg, $sym, $ref, $attr, $data, $phase) = @_;
#
#		croak "can't declare a blessed variable as :Req" if blessed($ref);
#
#		my $name = var_name(4, $ref);
#
#		my $request;
#		if (defined $data) {
#			my $my = peek_my(4);
#			croak "Unknown request object '$data'" unless (
#				exists $my->{$data}
#				and reftype($my->{$data}) eq "REF"
#				and UNIVERSAL::isa(${$my->{$data}}, "POE::Request")
#			);
#			$request = ${$my->{$data}};
#		}
#		else {
#			$request = POE::Request->_get_current_request();
#		}
#
#		# Alias the attributed lexical variable with the appropriate
#		# request member.
#
#		my $stage = tied(%{POE::Request->_get_current_stage()});
#		my $hash = $stage->_request_context_fetch($request->get_id(), $name);
#		unless (defined $hash) {
#			$hash = { };
#			$stage->_request_context_store($request->get_id(), $name, $hash);
#		}
#
#		lexalias(4, $name, $hash);
#	}
#
#	sub Req :ATTR(ARRAY,RAWDATA) {
#		my ($pkg, $sym, $ref, $attr, $data, $phase) = @_;
#
#		croak "can't declare a blessed variable as :Req" if blessed($ref);
#
#		my $name = var_name(4, $ref);
#
#		my $request;
#		if (defined $data) {
#			my $my = peek_my(4);
#			croak "Unknown request object '$data'" unless (
#				exists $my->{$data}
#				and reftype($my->{$data}) eq "REF"
#				and UNIVERSAL::isa(${$my->{$data}}, "POE::Request")
#			);
#			$request = ${$my->{$data}};
#		}
#		else {
#			$request = POE::Request->_get_current_request();
#		}
#
#		# Alias the attributed lexical variable with the appropriate
#		# request member.
#
#		my $stage = tied(%{POE::Request->_get_current_stage()});
#		my $array = $stage->_request_context_fetch($request->get_id(), $name);
#		unless (defined $array) {
#			$array = [ ];
#			$stage->_request_context_store($request->get_id(), $name, $array);
#		}
#
#		lexalias(4, $name, $array);
#	}
#
#	### XXX - Experimental :Arg handler.
#	# TODO - Support other types?
#
#	sub Arg :ATTR(SCALAR,RAWDATA) {
#		my ($pkg, $sym, $ref, $attr, $data, $phase) = @_;
#		croak "can't register blessed things as Arg fields" if blessed($ref);
#		croak "can only register scalars as Arg fields" if ref($ref) ne "SCALAR";
#
#		my $name = var_name(4, $ref);
#		$name =~ s/^\$//;
#
#		package DB;
#		my @x = caller(4);
#		$$ref = $DB::args[1]{$name};
#	}
#
#	### XXX - Experimental :Memb handlers.
#
#	sub Self :ATTR(SCALAR,RAWDATA) {
#		my $ref = $_[2];
#		croak "can't register blessed things as Memb fields" if blessed($ref);
#
#		my $name = var_name(4, $ref);
#
#		my $self;
#		{
#			package DB;
#			my @x = caller(4);
#			$self = $DB::args[0];
#		}
#
#		my $tied_self = tied(%$self);
#		unless ($tied_self->_self_exists($name)) {
#			my $new_scalar;
#			$tied_self->_self_store($name, \$new_scalar);
#		}
#
#		lexalias(4, $name, $tied_self->_self_fetch($name));
#	}
#
#	sub Self :ATTR(ARRAY,RAWDATA) {
#		my $ref = $_[2];
#		croak "can't register blessed things as Memb fields" if blessed($ref);
#
#		my $name = var_name(4, $ref);
#
#		my $self;
#		{
#			package DB;
#			my @x = caller(4);
#			$self = $DB::args[0];
#		}
#
#		my $tied_self = tied(%$self);
#		unless ($tied_self->_self_exists($name)) {
#			$tied_self->_self_store($name, []);
#		}
#
#		lexalias(4, $name, $tied_self->_self_fetch($name));
#	}
#
#	sub Self :ATTR(HASH,RAWDATA) {
#		my $ref = $_[2];
#		croak "can't register blessed things as Memb fields" if blessed($ref);
#
#		my $name = var_name(4, $ref);
#
#		my $self;
#		{
#			package DB;
#			my @x = caller(4);
#			$self = $DB::args[0];
#		}
#
#		my $tied_self = tied(%$self);
#		unless ($tied_self->_self_exists($name)) {
#			$tied_self->_self_store($name, {});
#		}
#
#		lexalias(4, $name, $tied_self->_self_fetch($name));
#	}
#}
#
#{
#	no warnings 'redefine';
#
#	sub Rsp :ATTR(SCALAR,RAWDATA) {
#		my ($pkg, $sym, $ref, $attr, $data, $phase) = @_;
#		#warn "pkg($pkg) sym($sym) ref($ref) attr($attr) data($data) phase($phase)\n";
#
#		croak "can't declare a blessed variable as :Rsp" if blessed($ref);
#
#		my $name = var_name(4, $ref);
#
#		# Alias the attributed lexical variable with the appropriate
#		# response member.
#
#		my $stage = POE::Request->_get_current_stage();
#		my $response_id = tied(%$stage)->_get_response()->get_id();
#
#		my $scalar = tied(%$stage)->_request_context_fetch($response_id, $name);
#		unless (defined $scalar) {
#			# Because I'm afraid to say $scalar = \$scalar.
#			my $new_scalar = undef;
#			$scalar = \$new_scalar;
#			tied(%$stage)->_request_context_store($response_id, $name, $scalar);
#		}
#
#		lexalias(4, $name, $scalar);
#	}
#
#	sub Rsp :ATTR(HASH,RAWDATA) {
#		my ($pkg, $sym, $ref, $attr, $data, $phase) = @_;
#		#warn "pkg($pkg) sym($sym) ref($ref) attr($attr) data($data) phase($phase)\n";
#
#		croak "can't declare a blessed variable as :Rsp" if blessed($ref);
#
#		my $name = var_name(4, $ref);
#
#		# Alias the attributed lexical variable with the appropriate
#		# response member.
#
#		my $stage = POE::Request->_get_current_stage();
#		my $response_id = tied(%$stage)->_get_response()->get_id();
#
#		my $hash = tied(%$stage)->_request_context_fetch($response_id, $name);
#		unless (defined $hash) {
#			$hash = { };
#			tied(%$stage)->_request_context_store($response_id, $name, $hash);
#		}
#
#		lexalias(4, $name, $hash);
#	}
#
#	sub Rsp :ATTR(ARRAY,RAWDATA) {
#		my ($pkg, $sym, $ref, $attr, $data, $phase) = @_;
#		#warn "pkg($pkg) sym($sym) ref($ref) attr($attr) data($data) phase($phase)\n";
#
#		croak "can't declare a blessed variable as :Rsp" if blessed($ref);
#
#		my $name = var_name(4, $ref);
#
#		# Alias the attributed lexical variable with the appropriate
#		# response member.
#
#		my $stage = POE::Request->_get_current_stage();
#		my $response_id = tied(%$stage)->_get_response()->get_id();
#
#		my $array = tied(%$stage)->_request_context_fetch($response_id, $name);
#		unless (defined $array) {
#			$array = { };
#			tied(%$stage)->_request_context_store($response_id, $name, $array);
#		}
#
#		lexalias(4, $name, $array);
#	}
#}

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

POE::Stage is too young for production use.  For example, its syntax
is still changing.  You probably know what you don't like, or what you
need that isn't included, so consider fixing or adding that.  It'll
bring POE::Stage that much closer to a usable release.

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
