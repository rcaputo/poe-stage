# $Id$

=head1 NAME

POE::Callback - object wrapper for callbacks with lexical closures

=head1 SYNOPSIS

	# TODO - Make this a complete working example.
	my $callback = POE::Callback->new(
		name => "Pkg::sub",
		code => \&coderef,
	);
  $callback->(@arguments);

=head1 DESCRIPTION

POE::Callback wraps coderefs in magic that makes certain lexical
variables persistent between calls.

It's used internally by the classes that comprise POE::Stage.

=cut

package POE::Callback;

use warnings;
use strict;

use PadWalker qw(var_name peek_my peek_sub);
use Scalar::Util qw(blessed reftype weaken);
use Devel::LexAlias qw(lexalias);
use Carp qw(croak);

# Track our wrappers to avoid wrapping them.  Otherwise hilarity may
# ensue.

my %callbacks;
use constant CB_SELF => 0;
use constant CB_NAME => 1;

=head2 new CODEREF

Creates a new callback from a raw CODEREF.  Returns the callback,
which is just the CODEREF blessed into POE::Callback.

=cut

sub new {
	my ($class, $arg) = @_;

	foreach my $required (qw(name code)) {
		croak "POE::Callback requires a '$required'" unless $arg->{$required};
	}

	my $code = $arg->{code};
	my $name = $arg->{name};

	# Don't wrap callbacks.
	return $code if exists $callbacks{$code};

	# Gather the names of persistent variables.
	my $pad = peek_sub($code);
	my @persistent = grep {
		/^\$(self|req|rsp)$/ || /^([\$\@\%])(req|rsp|arg|self)_(\S+)/
	} keys %$pad;

	# No point in the wrapper if there are no persistent variables.

	unless (@persistent) {
		my $self = bless $code, $class;
		return $self->_track($name);
	}

	my $self = bless sub {

		# Cache these for speed.
		my ($self, $tied_self, $arg, $req, $rsp);

		my $pad = peek_sub($code);
		foreach my $var_name (@persistent) {
			my $var_reference = $pad->{$var_name};

			if ($var_name eq '$self') {
				$self = POE::Stage::self() unless defined $self;
				lexalias($code, $var_name, \$self);
				next;
			}

			if ($var_name eq '$req') {
				unless (defined $req) {
					unless (defined $tied_self) {
						$self = POE::Stage::self() unless defined $self;
						$tied_self = tied(%$self);
					}
					$req = $tied_self->_get_request();
				}

				lexalias($code, $var_name, \$req);
				next;
			}

			if ($var_name eq '$rsp') {
				unless (defined $rsp) {
					unless (defined $tied_self) {
						$self = POE::Stage::self() unless defined $self;
						$tied_self = tied(%$self);
					}
					$rsp = $tied_self->_get_response();
				}

				lexalias($code, $var_name, \$rsp);
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
					$self = POE::Stage::self() unless defined $self;
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

				lexalias($code, $var_name, $member_ref);
				next;
			}

			if ($prefix eq 'rsp') {
				unless (defined $rsp) {
					unless (defined $tied_self) {
						$self = POE::Stage::self() unless defined $self;
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

				lexalias($code, $var_name, $member_ref);
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
					$self = POE::Stage::self() unless defined $self;
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

				lexalias($code, $var_name, $member_ref);

				next;
			}
		}

		goto $code;
	}, $class;

	return $self->_track($name);
}

# Track a callback so we don't accidentally wrap it.

sub _track {
	my ($self, $name) = @_;
	$callbacks{$self} = [
		$self,  # CB_SELF
		$name,  # CB_NAME
	];
	weaken($callbacks{$self}[CB_SELF]);
	return $self;
}

# When the callback object is destroyed, it's also removed from the
# tracking hash.

sub Destroyer::DESTROY {
	my $self = shift;
	warn "!!! Destroying untracked callback $self" unless (
		exists $callbacks{$self}
	);
	delete $callbacks{$self};
}

# End-of-run leak checking.

END {
	if (keys %callbacks) {
		warn "!!! callback leak:";
		foreach my $callback (sort keys %callbacks) {
			warn "!!!   $callback = ", $callbacks{$callback}[CB_NAME], "\n";
		}
	}
}

1;
