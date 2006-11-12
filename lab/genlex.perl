#!perl
# $Id$

# The magical lexical tour is coming to take you away, ha ha.
#
# Support the creation of an arbitrary number of lexical states that
# will persist between function calls.  Apply them to a function for
# each call.
#
# Provide a second way to do this, using a wrap() call.  wrap()
# generates and returns a wrapper which does the magical lexical
# application for you.
#
# Prefixes (such as "arg_") determine which context will be used.  The
# default variable parser ignores lexicals with a leading underscore,
# so those are always dynamic.

use warnings;
use strict;

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

print "The long way:\n";

# Define a set of contexts that will persist between multiple calls.
# Keys are context names.  The default variable parser and context
# accessor alias $foo_member to \$context{foo}{'$member'}.

my %persistent_contexts;

# Define an arguments context, and install it into our set.  If not
# present, $arg_foo will not be treated specially.

my ($arg_context, $arg_accessor) = generate_arg_context();
$persistent_contexts{arg} = $arg_accessor;

# Define a default, catch-all conext, and install it into our set.
# This is required.  The underscore is used because the default
# variable parser doesn't allow them in context names.

$persistent_contexts{_} = (generate_plain_context())[1];

# Call the function a few times, varying the arguments but otherwise
# leaving the context set intact between calls.

foreach my $number (qw(one two three four five)) {
  %$arg_context = ( number => $number );
  call \&target, \%persistent_contexts, \&default_var_parser;
}

### Whee!  Now the short way.

print "The short way:\n";

# Wrap the sub in a thunk that does all the above for us.
# Nifty: We can create multiple thunks for a single target.  Each has
# separate contexts.

my $thunk = wrap \&target;
foreach my $number (qw(one two three four five)) {
  $thunk->(number => $number);
}

### Now let's try it with POE!

use POE;

sub spawn {
  # Generate an accessor for the heap.

  my ($new_heap, $heap_accessor) = generate_plain_context();
  my %ctx = (
    heap => $heap_accessor,
  );

  # Get event handler parameters.  Turn them into hashes.

  sub poe_getter {
    package DB;
    my @x = caller(1);
    use POE::Session;
    my %param = map { $_ - ARG0, $DB::args[$_] } (ARG0..$#DB::args);
    return %param;
  }

  # Convenient abstraction to wrap().
  
  sub poe_wrap {
    my ($handler, $context) = @_;
    wrap($handler, $context, undef, undef, \&poe_getter);
  }

  # Create a session.  Its moo handler will be lexically wrapped.

  POE::Session->create(
    heap => $new_heap,
    inline_states => {
      _start => sub { $_[KERNEL]->yield(moo => 0 ) },
      moo    => poe_wrap(\&handle_moo, \%ctx),
    }
  );

  sub handle_moo {
    my $arg_0; # magic
    my $heap_foo++;
    print "count = $arg_0 ... heap = $heap_foo\n";
    $_[KERNEL]->yield(moo => $arg_0 + 1 );
  }
}

spawn();
POE::Kernel->run();

exit;

### Implement the hounds!

# Wrap a function with persistent contexts.

sub wrap ($;$$$$) {
  my ($target, $contexts, $var_parser, $arg_generator, $param_getter) = @_;

  # Default some things.

  $contexts      ||= { };
  $var_parser    ||= \&default_var_parser;
  $contexts->{_} ||= (generate_plain_context())[1];
  $arg_generator ||= \&generate_arg_context;
  $param_getter  ||= \&default_param_getter;

  my ($arg_context, $arg_accessor) = $arg_generator->();
  $contexts->{arg} = $arg_accessor;

  return sub {
    %$arg_context = $param_getter->(@_);
    call($target, $contexts, $var_parser, \@_);
  }
}

# Call a function with a persistent context and some parameters.

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
# member if necessary.

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

# Helper.  Default variable parser.  These must return nothing for
# uninteresting variables, otherwise three values:  The parsed sigil,
# the variable prefix (or the catch-all, "_"), and the base member
# name.

sub default_var_parser {
  my ($contexts, $var) = @_;

  return unless (
    my ($sigil, $pfx, $member) = $var =~ /^([\$\@\%])(?!_)(?:([^_]*)_)?(\S+)/
  );

  $pfx = "_" unless defined $pfx;
  unless (exists $contexts->{$pfx}) {
    # Not a valid prefix.
    # Put the prefix back on the base, and use the catch-all.
    $member = $pfx . "_" . $member;
    $pfx = "_";
  }

  return $sigil, $pfx, $member;
}

# Helper.  Generate a plain context and its accessor.  Plain context
# member names include their sigils.  Returns the new context variable
# and its accessor.

sub generate_plain_context {
  my %new_context;
  return \%new_context, sub {
    my ($sigil, $member) = @_;
    get_member_ref(\%new_context, $sigil, "$sigil$member");
  };
}

# Helper.  Generate an arguments context and its accessor.  Return
# them both, in that order.  By convention, argument data member names
# don't include their sigils.

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
