#!perl
# $Id$

# Support an arbitrary number of lexical states that will persist
# between function calls.  Apply them to a function for each call.
#
# Prefixes (such as "arg_") determine which context will be used.  The
# default variable parser ignores lexicals beginning with an
# underscore.  Underscored lexicals are always dynamic.
#
# Provide a wrap() call that returns a wrapped version of a function.
# The wrapped version does the call() magic internally.  Externally it
# looks like a normal function.
#
# Customize wrap() so it works with POE.

use warnings;
use strict;

use lib qw(./lib ../lib);

use Devel::LexAlias qw(lexalias);
use PadWalker qw(peek_sub);

# Forward declarations required if we're doing this.

sub call ($$$;$);
sub wrap ($;$$$$);

# A simple function with persistent state.

sub target {
  my $arg_number;   # Parameter.
  my $narf_x++;     # Persistent.
  my $_i++;         # Dynamic.
  my $j++;          # Persistent.

  print "  target arg_number($arg_number) narf_x($narf_x) _i($_i) j($j)\n";
}

### First the long way.

# 1. Define a set of contexts that will persist between multiple
# calls.  Keys are context names.  The default variable parser and
# context accessor alias $foo_member to \$context{foo}{'$member'}.
#
# 2. Define an arguments context, and install it into our set.  If not
# present, $arg_foo will not be treated specially.
#
# 3. Define a default, catch-all conext, and install it into our set.
# This is required.  The catch-all context's name must agree with the
# one the variable parser will use.
#
# 4. Call the function a few times, varying the arguments but
# otherwise leaving the context set intact between calls.

print "The long way:\n";

my %persistent_contexts;

my ($arg_context, $arg_accessor) = generate_arg_context();
$persistent_contexts{arg} = $arg_accessor;

$persistent_contexts{_} = (generate_plain_context())[1];

foreach my $number (qw(one two three four five)) {
  %$arg_context = ( number => $number );
  call \&target, \%persistent_contexts, \&default_var_parser;
}

### Whee!  Now the short way.

# Wrap the sub in a thunk that does all the above for us.  We can
# wrap() the same function multiple times, and each wrapper will
# manage its own set of contexts.

print "The short way:\n";

my $thunk = wrap \&target;
foreach my $number (qw(one two three four five)) {
  $thunk->(number => $number);
}

### Now let's try it with POE!

print "The POE way:\n";

use POE;
spawn();
POE::Kernel->run();

# Spawn a new session.
#
# 1. Generate a context for the heap.  Save it is the set of contexts
# that will be passed to poe_wrap().
#
# 2. Create the new session, using the heap context as its heap.  Its
# "moo" event is handled by a wrapped version of handle_moo().  The
# wrapped version will access arguments as $arg_0.. and heap variables
# as $heap_foo.
#
# TODO - Allow spawn() to be called with the inline_states hash.  Wrap
# the handlers internally.

sub spawn {
  my ($new_heap, $heap_accessor) = generate_arg_context();
  my %contexts = ( heap => $heap_accessor );

  POE::Session->create(
    heap => $new_heap,
    inline_states => {
      _start => sub { $_[KERNEL]->yield(moo => 0) },
      moo    => poe_wrap(\&handle_moo, \%contexts),
    }
  );
}

# The magical wrapped handler.
#
# We still haven't dealt with $_[HEAP] or $_[KERNEL] in handle_moo(),
# but arguments and heap variables are accessible through lexical
# aliasing.  Note that POE's existing @_ arguments are intact.  Also
# that $heap_foo and $_[HEAP]{foo} are semantically identical.

sub handle_moo {
  my $arg_0++;     # magic
  my $heap_foo++;  # more magic

  print "  count = $arg_0 ... heap = $heap_foo ... heap b = $_[HEAP]{foo}\n";
  $_[KERNEL]->yield(moo => $arg_0) if $arg_0 < 10;
}

# Helper.  Define a argument "getter" function.  This is used in the
# wrapper to translate POE's @_[ARG0..$#_] into %$arg_context.  Each
# argument in the context is keyed on its position: ARG0 =
# $arg_context->{0}.  The lexical $arg_0 is aliased to ARG0 through
# other rules.

sub poe_getter {
  package DB;
  my @x = caller(1);
  use POE::Session;
  my %param = map { $_ - ARG0, $DB::args[$_] } (ARG0..$#DB::args);
  return %param;
}

# Helper.  Wrap a POE handler.  It's a thin wrapper around wrap().

sub poe_wrap {
  my ($handler, $context) = @_;
  wrap($handler, $context, undef, undef, \&poe_getter);
}

### Implement the hounds!

# Wrap a function with persistent contexts.

sub wrap ($;$$$$) {
  my ($target, $contexts, $var_parser, $arg_generator, $param_getter) = @_;

  $contexts      ||= { };
  $var_parser    ||= \&default_var_parser;
  $contexts->{_} ||= (generate_plain_context())[1];  # agree with var parser
  $arg_generator ||= \&generate_arg_context;
  $param_getter  ||= \&default_param_getter;

  # Generate and save an argument context.

  my ($arg_context, $arg_accessor) = $arg_generator->();
  $contexts->{arg} = $arg_accessor;

  # Return a wrapped subroutine.

  return sub {
    %$arg_context = $param_getter->(@_);
    call($target, $contexts, $var_parser, \@_);
  }
}

# Call a function, setting up persistent contexts within it.

sub call ($$$;$) {
  my ($sub, $contexts, $var_parser, $orig_args) = @_;

  # Alias lexicals to contexts.

  my $pad = peek_sub($sub);
  while (my ($var, $ref) = each %$pad) {
    next unless my ($sigil, $pfx, $member) = $var_parser->($contexts, $var);
    lexalias( $sub, $var, $contexts->{$pfx}->($sigil, $member) );
  }

  $sub->(@$orig_args);
}

# Helper.  Return a reference to a member of a hash, autovivifying the
# member if necessary.  Scalars are not stored by reference, otherwise
# argument hashes would require scalar references as well.

sub get_member_ref ($$$) {
  my ($hash, $sigil, $member) = @_;

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

# Helper.  Default variable parser.
#
# Variable parsers take two parameters: A contexts hash and a variable
# name.  They return three values: The variable's sigil, the name of
# the context it belongs to, and the name of the member within that
# context.
#
# The default parser prohibits context names containing an underscore,
# so these can be used internally.  The catch-all context is simply
# "_".  This will be important in other places.

sub default_var_parser {
  my ($contexts, $var) = @_;

  return unless (
    my ($sigil, $pfx, $member) = $var =~ /^([\$\@\%])(?!_)(?:([^_]*)_)?(\S+)/
  );

  $pfx = "_" unless defined $pfx;

  # The prefix is not a known context.  Put it back on the member
  # name, and use the catch-all instead.

  unless (exists $contexts->{$pfx}) {
    $member = $pfx . "_" . $member;
    $pfx = "_";
  }

  return $sigil, $pfx, $member;
}

# Helper.  Generate a plain context and its accessor.  Plain context
# member names include their sigils.  Returns the new context and its
# accessor.

sub generate_plain_context {
  my %new_context;
  return \%new_context, sub {
    my ($sigil, $member) = @_;
    get_member_ref(\%new_context, $sigil, "$sigil$member");
  };
}

# Helper.  Generate an arguments context and its accessor.  By
# convention, argument members do not include their sigils.

sub generate_arg_context {
  my %new_context;
  return \%new_context, sub {
    my ($sigil, $member) = @_;
    get_member_ref(\%new_context, $sigil, $member);
  };
}

# Helper.  Retrieve the called function's parameters, returning a hash
# reference of name/value pairs.

sub default_param_getter {
  @_;
}
