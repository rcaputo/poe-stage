# $Id$

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

=head1 CONSTRUCTOR

=head2 new

Spawn a new POE::Stage object.  Performs housekeeping within
POE::Stage and related classes and passes parameters and execution to
init() for further initialization.

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

	$self->init(\%args);

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

=head1 DESCRIPTION

The POE::Stage object system consists of reusable components called
stages.  Stages receive requests, perform their tasks, and return
results.

Stages are Perl objects.  They are inheritable, and can do most normal
things.  However, subclasses are discouraged from overriding the new()
method.

=cut
