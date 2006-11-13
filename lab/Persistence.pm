# $Id$

=head1 NAME

Lexical::Persistence - Persistent lexical variable values for arbitrary calls.

=head1 SYNOPSIS

	#!/usr/bin/perl

	use Lexical::Persistence;

	my $persistence = Lexical::Persistence->new();
	foreach my $number (qw(one two three four five)) {
		$persistence->call(\&target, number => $number);
	}

	exit;

	sub target {
		my $arg_number;   # Parameter.
		my $narf_x++;     # Persistent.
		my $_i++;         # Dynamic.
		my $j++;          # Persistent.

		print "arg_number($arg_number) narf_x($narf_x) _i($_i) j($j)\n";
	}

=head1 DESCRIPTION

Lexical::Persistence objects encapsulate persistent data.  Lexical
variables in the functions they call are used to access this
persistent data.  The usual constructor, new(), creates new
persistence objects.

The persistence object's call() method is used to call functions
within their persistent contexts.

By default, lexicals without a leading underscore are persistent while
ones with the underscore are not.  parse_variable() may be overridden
to change this behavior.

A single Lexical::Persistence object can encapsulate multiple
persistent contexts.  Each context is configured with a set_context()
call.

By default, parse_variable() determines the context to use by
examining the characters leading up to the first underscore in a
variable's name.

The get_member_ref() returns a reference to the persistent value for a
given lexical variable.  The lexical will be aliased to the referenced
value returned by this method.

By default, push_arg_context() translates named function parameters
into values within the "arg" context.  The parameters are then
available as $arg_name lexicals within call()'s target function.

pop_arg_context() is used to restore a previous argument context after
a target function returns.

A helper method, wrap(), returns a coderef that, when called normally,
does call() magic internally.

By default, lexicals without prefixes persist in a catch-all context
named "_".  The underscore is used because it's parse_variable()'s
context/member separator.  The initialize_contexts() member is called
during new() to create initial contexts such as "_".

The get_context() accessor can be used to fetch a named context hash
for more detailed manipulation of its values.

=cut

package Persistence;

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

=head2 get_context NAME

Returns a context hash associated with a particular context name.
Autovivifies the context if it doesn't already exist.

=cut

sub get_context {
	my ($self, $context_name) = @_;
	$self->{context}{$context_name} ||= { };
}

=head2 call CODEREF, PARAMETER_LIST

Call CODEREF with lexical persistence.

The PARAMETER_LIST is passed to the callee in the usual Perl way.  It
may also be stored in an "argument context", as determined by
push_arg_context().

Lexical variables within the callee will be restored from the current
context.  parse_variable() determines which variables are aliased and
which contexts they belong to.

=cut

sub call {
	my ($self, $sub, @args) = @_;

	my $old_arg_context = $self->push_arg_context(@args);

	my $pad = peek_sub($sub);
	while (my ($var, $ref) = each %$pad) {
		next unless my ($sigil, $context, $member) = $self->parse_variable($var);
		lexalias(
			$sub, $var, $self->get_member_ref($sigil, $context, $member)
		);
	}

	unless (defined wantarray) {
		$sub->(@args);
		$self->pop_arg_context($old_arg_context);
		return;
	}

	if (wantarray) {
		my @return = $sub->(@args);
		$self->pop_arg_context($old_arg_context);
		return @return;
	}

	my $return = $sub->(@args);
	$self->pop_arg_context($old_arg_context);
	return $return;
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

=head2 push_arg_context PARAMETER_LIST

Convert a PARAMETER_LIST into members of an argument context.  By
default, the context is named "arg", so $arg_foo will contain the
value of the "foo" parameter.

=cut

sub push_arg_context {
	my $self = shift;
	my $old_arg_context = $self->get_context("arg");
	$self->set_context( arg => { @_ } );
	return $old_arg_context;
}

=head2 pop_arg_context OLD_ARG_CONTEXT

Restore the OLD_ARG_CONTEXT after a target function is called.  The
OLD_ARG_CONTEXT was returned by push_arg_context().

=cut

sub pop_arg_context {
	my ($self, $old_context) = @_;
	$self->set_context( arg => $old_context );
}

=head1 BUGS

Read them at
http://rt.cpan.org/Public/Dist/Display.html?Name=lexical-persistence

Report them at
http://rt.cpan.org/Public/Bug/Report.html?Queue=lexical-persistence

=head1 SEE ALSO

L<POE::Stage>, L<Devel::LexAlias>, L<PadWalker>,
L<Catalyst::Controller::BindLex>.

=head1 LICENSE

Lexical::Persistence in copyright 2006 by Rocco Caputo.  All rights
reserved.  Lexical::Persistence is free software.  It is released
under the same terms as Perl itself.

=head1 ACKNOWLEDGEMENTS

Thanks to Matt Trout and Yuval Kogman for lots of inspiration.  They
were the devil and the other devil sitting on my shoulders.

Nick Perez convinced me to make this a class rather than persist with
the original, functional design.

irc://irc.perl.org/poe for support and feedback.

=cut

1;
