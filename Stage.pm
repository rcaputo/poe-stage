# $Id$

package Stage;

use warnings;
use strict;

use POE::Kernel;
use POE::Session;

use Scalar::Util qw(blessed);
use Carp qw(croak);
use Call;
use TiedStage;

use Attribute::Handlers;

sub DEBUG () { 0 }
sub DEBUG_ATTRIBUTES () { 0 }

sub METH_CODEREF () { 0 }
sub METH_TYPE    () { 1 }
sub METH_DATA    () { 2 }
sub METH_PHASE   () { 3 }

my %stage_classes;

# Singleton.  All objects will be run from here.  Later we may want to
# start new objects in separate sessions.  For threading, for example.

my $session_id = POE::Session->create(
	inline_states => {
		_start => sub {
			$_[KERNEL]->alias_set(__PACKAGE__),
		},

		# Handle a POE timer.  Figure out the Pow:: class that caused
		# its firing.  From there determine the Stage and method to
		# call.  Then call it!
		#
		# Expects two arguments:
		# ARG0 = The "name" of the timer object that set the event to be
		#        fired.  Really a stringified object reference.
		stage_timer => sub {
			my ($timer_object, $call) = @_[ARG0, ARG1];
			$timer_object = $call->find_resource($timer_object);

			return unless $timer_object;

			# Put the context back into the call that created it.
			$call->_activate();
			my $method = "actual_" . $timer_object->method();
			my $stage = $call->destination_stage();

			# XXX - Not tracking wantarray here.
			$stage->$method($call);

			$call->_deactivate();

			# TODO - Maybe not, if the resource has been again()'d.
			$call->unregister_resource($timer_object);
		},
		stage_call => sub {
			my $call = $_[ARG0];

#				warn "stage_call($call)";

			$call->_activate();

			eval { $call->_receive(); };
			if (0 and $@) {
				warn $@;
				use YAML qw(Dump);
				warn Dump $call;
				die "@_";
			}

			my ($stage, $method) = $call->destination();

			# XXX - Not tracking wantarray here.
			$stage->$method($call);

			$call->_deactivate();
		},
	},
)->ID;

# The sync attribute does nothing.  We still must declare it as valid.

sub sync :ATTR(CODE) {
  my ($package, $symbol, $referent, $attr, $data, $phase) = @_;
  my $method = *{$symbol}{NAME};

	# TODO
	# Generate a proper thunk here.  Even though we're calling it
	# synchronously, we still must reform the parameters into what the
	# callee expects.

	if (DEBUG_ATTRIBUTES) {
		my $print_data = $data;
		$print_data = "" unless defined $print_data;

    warn(
			ref($referent), " $method ($referent) was just declared\n",
			"\tin package $package\n",
			"\tand ascribed the '$attr' attribute\n",
			"\twith data ($print_data)\n",
			"\tin phase $phase\n"
		);
	}

	$stage_classes{$package}{$method} = [
		$referent,  # METH_CODEREF
		$attr,      # METH_TYPE
		$data,      # METH_DATA
		$phase,     # METH_PHASE
	];
}

# The async method replaces the class method with a thunk that creates
# a Call to do the dirty work.

sub async :ATTR(CODE) {
  my ($package, $symbol, $referent, $attr, $data, $phase) = @_;
  my $method = *{$symbol}{NAME};

	# TODO
	# Generate a proper thunk here.

	if (DEBUG_ATTRIBUTES) {
		my $print_data = $data;
		$print_data = "" unless defined $print_data;

    warn(
			ref($referent), " $method ($referent) was just declared\n",
			"\tin package $package\n",
			"\tand ascribed the '$attr' attribute\n",
			"\twith data ($print_data)\n",
			"\tin phase $phase\n"
		);
	}

	$stage_classes{$package}{$method} = [
		$referent,  # METH_CODEREF
		$attr,      # METH_TYPE
		$data,      # METH_DATA
		$phase,     # METH_PHASE
	];
}

sub is_async {
	my ($class, $method) = @_;
	return unless (
		exists $stage_classes{$class} and
		exists $stage_classes{$class}{$method}
	);
	return $stage_classes{$class}{$method}[METH_TYPE] eq "async";
}

# INIT is called after CHECK and before the program begins running.
# This gives us the opportunity to cross-check attributes and to
# register synchronous thunks for methods that don't have attributes.

sub INIT {

	warn "INIT now";

	# Walk the package tree.  Find packages that are stages, and make
	# sure their methods have been madnessed.

	my @packages = qw(main);
	my %visited_packages;

	while (@packages) {
		my $pkg = shift @packages;
		next if $visited_packages{$pkg}++;

		# What in hell is this?!
		next if $pkg eq "<none>";

		# Abandon all hope ye who enter here.
		no strict 'refs';

		# Walk the package's symbol table.
		# Enter sub-packages into the list to walk through.
		my @sub_packages = grep /::$/, sort keys %{"$pkg\::"};
		foreach my $sub_package (@sub_packages) {
			$sub_package =~ s/::$//;
			unless ($pkg eq "main") {
				substr($sub_package, 0, 0) = "$pkg\::";
			}
			push @packages, $sub_package;
		}

		# Must be a subclass of Stage, but not Stage itself.
		next unless $pkg->isa("Stage") and $pkg ne "Stage";

		# Record the subclass for the next pass.
		# TODO - Combine into a single pass.
		unless (exists $stage_classes{$pkg}) {
			$stage_classes{$pkg} = { };
		}
	}

	# Now make sure all the methods in the Stage classes are madnessed.
	# TODO - Migrate this into the previous loop.

	foreach my $pkg (keys %stage_classes) {
		unless ($pkg->isa("Stage")) {
			warn "Class $pkg uses Stage.pm but is not a Stage.\n";
			next;
		}

		no strict 'refs';

		print "  $pkg\n";
		my @symbols = keys %{"$pkg\::"};
		foreach my $symbol (@symbols) {
			next if $symbol eq "return";

			my $sub = *{"$pkg\::$symbol"}{CODE};
			next unless defined $sub;
			print "    $pkg -> $symbol = $sub\n";

			# Implicit :sync attribute.

			unless (exists $stage_classes{$pkg}{$symbol}) {
				print "      (implicit sync)\n";
				$stage_classes{$pkg}{$symbol} = [
					$sub,   # METH_CODEREF
					"sync", # METH_TYPE
					undef,  # METH_DATA
					"INIT", # METH_PHASE
				];
			}
			else {
				print "      (explicit $stage_classes{$pkg}{$symbol}[METH_TYPE])\n";
			}

			# Some subs must be synchronous, like init().
			# TODO - Validate them.

			# Replace the thing with its thunk.
			my $meth_rec = $stage_classes{$pkg}{$symbol};
			my $meth_sub = $meth_rec->[METH_CODEREF];

			# Synchronous calls.  Build a call frame, and call the actual
			# method with it.  Return whatever the actual method does, being
			# careful to mind the context of the call.

			if ($meth_rec->[METH_TYPE] eq "sync") {
				no warnings 'redefine';

				*{"$pkg\::actual_$symbol"} = $meth_sub;
				*{"$pkg\::$symbol"} = sub {
					my ($self, %arg) = @_;

					if (DEBUG) {
						warn "$self->$symbol(%arg)";
					}

					my $actual_symbol = "actual_$symbol";

					my $c = Call->new(
						_stage  => $self,
						_method => $symbol,
						%arg
					);

					# XXX - Copied/pasted from stage_call's handler.  Probably
					# should make it a sub, eh?  Or perhaps a method on Call?
					$c->_activate();

					eval { $c->_receive(); };
					if (0 and $@) {
						warn $@;
						use YAML qw(Dump);
						warn Dump $c;
						die "@_";
					}

					my ($stage, $method) = $c->destination();

					# Track wantarray, because the return value is important.
					my @retval;
					if (wantarray) {
						@retval = $stage->$actual_symbol($c);
					}
					elsif (defined wantarray) {
						$stage->$actual_symbol($c);
					}
					else {
						$retval[0] = $stage->$actual_symbol($c);
					}

					$c->_deactivate();

					return @retval;
				};

				next;
			}

			# Asynchronous call.  Transform the call into a post that will
			# eventually do the right thing.

			if ($meth_rec->[METH_TYPE] eq "async") {
				no warnings 'redefine';
				*{"$pkg\::actual_$symbol"} = $meth_sub;
				*{"$pkg\::$symbol"} = sub {
					my ($self, %arg) = @_;

					if (DEBUG) {
						warn "$self->$symbol(%arg)";
					}

					my $c = Call->new(
						_stage  => $self,
						_method => "actual_$symbol",
						%arg
					);

					$c->call();

					return $c;
				};

				next;
			}

			die "unknown method type '$meth_rec->[METH_TYPE]'";
		}
	}
}

# Import is called wherever this module is used.  That is, it's called
# in all Stage classes.  The import() sub registers the package name
# so that other subs within the package can default to synchronous.

sub import {
	my ($class, $signature) = @_;

	return unless $class eq __PACKAGE__;

	my ($pkg, $file, $line) = caller();

	warn "$pkg called $class->import() at $file line $line\n";

	return if exists $stage_classes{$pkg};
	$stage_classes{$pkg} = { };
}

sub new {
	my $class = shift;
	croak "$class->new(...) requires an even number of parameters" if @_ % 2;

	my %arg = @_;

	tie my(%self), "TiedStage";
	my $self = bless \%self, $class;

	$self->init(%arg);

	return $self;
}

sub get_sid {
	return $session_id;
}

sub run {
	POE::Kernel->run();
}

1;

__END__

=head1 NAME

Stage - A small wrapper around POE::Session to track Call states.

=head1 SYNOPSIS

Stage is a subclass of POE::Session.  It does not alter its base
class' public interface.

=head1 DESCRIPTION

Stage is a thin wrapper for POE::Session.  It tracks the current Call
context so that return() will work properly.  The tracking should also
be useful for future features.

You just need to remember one thing: Use Stage wherever you would
normally use POE::Session when you're working with Call objects.

=head1 BUGS

Event handler contexts are not maintained.  Event handler return
values are not returned.  Don't look at me like that!  We're
experimenting with a whole new set of call and return semantics, so we
don't NEED wantarray() and to preserve return values!

Well, not this early in the experiment, anyway.  :)

=head1 FUTURE

I'd like to create a set of classes to wrap POE::Kernel APIs.  Like
Delay, Alarm, Select, and so on.  They would automagically register
themselves with the current Session AND the current Call.  In theory,
when a Call destructs after return, all its little resources would
clean themselves up without being tracked explicitly.  That's just too
cool for words if it works.

=head1 LICENSE AND AUTHOR

Call is Copyright 2005 by Rocco Caputo.  All rights are reserved.  You
may modify and distribute this code under the same terms as Perl
itself.

=cut
