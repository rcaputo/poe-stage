# $Id$

package Persistence;  # planned name: Lexical::Persistence

use warnings;
use strict;

use Devel::LexAlias qw(lexalias);
use PadWalker qw(peek_sub);

=head2 new

Create a new lexical persistence object.

=cut

sub new {
	my $class = shift;

	my $self = bless {
		context => { },
	}, $class;

	$self->initialize_contexts();

	return $self;
}

=head2 initialize_contexts

Set whatever standard contexts belong to this class.  By default, a
catch-all conext is set.

=cut

sub initialize_contexts {
	my $self = shift;
	$self->set_context( _ => { } );
}

=head2 set_context NAME, HASH

Store a context HASH within the persistence object, keyed on a NAME.
Contexts stored in the object will be shared among all the functions
called through this object.

parse_variable() will choose which lexicals are persistent and the
names of their contexts.

=cut

sub set_context {
	my ($self, $context_name, $context_hash) = @_;
	$self->{context}{$context_name} = $context_hash;
}

=head2 call CODEREF, PARAMETER_LIST

Call CODEREF with lexical persistence.

The PARAMETER_LIST is passed to the callee in the usual Perl way.  It
may also be stored in an "argument context", as determined by
generate_arg_hash().

Lexical variables within the callee will be restored from the current
context.  parse_variable() determines which variables are aliased and
which contexts they belong to.

=cut

sub call {
	my ($self, $sub, @args) = @_;

	if (my ($arg_prefix, $arg_hash) = $self->generate_arg_hash(@args)) {
		$self->set_context($arg_prefix, $arg_hash)
	}

	my $pad = peek_sub($sub);
	while (my ($var, $ref) = each %$pad) {
		next unless my ($sigil, $context, $member) = $self->parse_variable($var);
		lexalias(
			$sub, $var, $self->get_member_ref($sigil, $context, $member)
		);
	}

	$sub->(@args);
}

=head2 wrap CODEREF

Wrap a function or anonymous CODEREF such that it's transparently
called via call().

=cut

sub wrap {
	my ($self, $sub) = @_;
	return sub {
		$self->call($sub, @_);
	};
}

=head2 parse_variable VARIABLE_NAME

Determines whether a VARIABLE_NAME is persistent.  If it is, return
the variable's sigil ("$", "@" or "%"), the context name where its
persistent value lives, and the member within that context where the
value is stored.

On the other hand, it returns nothing if VARIABLE_NAME is not
persistent.

=cut

sub parse_variable {
	my ($self, $var) = @_;

	return unless (
		my ($sigil, $context, $member) = (
			$var =~ /^([\$\@\%])(?!_)(?:([^_]*)_)?(\S+)/
		)
	);

	if (defined $context) {
		if (exists $self->{context}{$context}) {
			return $sigil, $context, $member;
		}
		return $sigil, "_", $context . "_" . $member;
	}

	return $sigil, "_", $member;
}

=head2 get_member_ref SIGIL, CONTEXT_NAME, MEMBER_NAME

Returns a reference to a persistent value.  The SIGIL defines the
member's type.  The CONTEXT_NAME and MEMBER_NAME describe where to
find the persistent value.

Scalar values are stored internally as scalars to be consistent with
how most people store scalars.

The persistent value is created if it doesn't exist.  The initial
value is undef or empty, depending on its type.

=cut

sub get_member_ref {
	my ($self, $sigil, $context, $member) = @_;

	my $hash = $self->{context}{$context};

	if ($sigil eq '$') {
		$hash->{$member} = undef unless exists $hash->{$member};
		return \$hash->{$member};
	}

	if ($sigil eq '@') {
		$hash->{$member} = [ ] unless exists $hash->{$member};
	}
	elsif ($sigil eq '%') {
		$hash->{$member} = { } unless exists $hash->{$member};
	}

	return $hash->{$member};
}

=head2 generate_arg_hash PARAMETER_LIST

Convert a PARAMETER_LIST into an argument context name and a hash
reference suitable for storing within the argument context.  The
default implementation supports $arg_foo variables by returning "arg"
and the contents of @_ untouched.

=cut

sub generate_arg_hash {
	my $self = shift;
	return arg => { @_ };
}

1;
