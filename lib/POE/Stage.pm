# $Id$

=head1 NAME

POE::Stage - a prototype base class for formalized POE components

=head1 SYNOPSIS

	# Note, this is not a complete program.
	# See the distribution's examples directory.

	my $stage = POE::Stage::Subclass->new();

	my $request = POE::Request->new(
		_stage  => $stage,          # Invoke this stage
		_method => "method_name",   # calling this method
		%parameter_pairs,           # with these parameters.
	);

=head1 DESCRIPTION

The POE::Stage object system consists of reusable, inheritable
components currently called stages.  Stages receive requests, perform
their tasks, and return results.

POE::Stage is a prototype base class for POE components.  It strives
to implement some of the most often used component patterns so that
component writers no longer need to.

It eliminates the need to manage most POE::Session objects directly.
Rather, the base class creates and maintains the sessions that drive
POE::Stage objects.

POE::Request and its subclasses formalize the way messages are passed
between components.

POE::Stage message handlers use a simple, consistent calling
convention.

It implements request-scoped data, eliminating most of the need for
explicitly dividing stage data into per-request spaces.  Per-request
data cleanup is automated when requests end.

It provides a consistent way to shut down stages: Destroy their
objects.

It manages a parent/child tree of request associations, tracking new
requests as children of existing ones.  Request cancellation is
automatically cascaded through the parent/child tree, canceling child
requests, grandchildren, and so on in a single operation.

It provides a class interface to POE::Kernel watchers through
POE::Watcher and its subclasses.

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
	},
)->ID();

sub _get_session_id {
	return $singleton_session_id;
}

=head2 new PAIRS

Create and return a new POE::Stage object, optionally passing
key/value PAIRS in its init() callback's $args parameter.  Unlike in
POE, you must save the object POE::Stage returns if you intend to use
it.

It is not recommended that subclasses override new.  Rather, they
should implement init() functions to initialize themselves after
instantiation.

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

=head2 init

init() is a virtual base method used to initialize POE::Stage objects
after construction.  Subclasses override this to perform their own
initialization.  The new() constructor will pass its public parameters
through to $self->init($key_value_pairs).

=cut

sub init {
	# Do nothing.  Don't even throw an error.
}

1;

=head1 BUGS

POE::Stage classes need a concise way to document their interfaces.
This full-on English narrative is inadequate.

=head1 SEE ALSO

POE::Request is the class that defines inter-stage messages.
POE::Watcher is the base class for event watchers, without which
POE::Stage won't run very well.

=head1 AUTHORS

Rocco Caputo <rcaputo@cpan.org>.

=head1 LICENSE

POE::Stage is Copyright 2005 by Rocco Caputo.  All rights are
reserved.  You may use, modify, and/or distribute this module under
the same terms as Perl itself.

=cut
