# $Id$

# A simple Delay class.  When tracking chains of Call objects, it
# becomes important to recall which Call a timer belongs to.

package Pow::Delay;

use warnings;
use strict;

use Carp qw(croak);
use POE::Kernel;

sub new {
	my $class = shift;
	my %args = @_;

	my $length = delete $args{length};
	croak "Delay requires a 'length'" unless defined $length;

	my $event = delete $args{event};
	croak "Delay requires an 'event'" unless defined $event;

	my $call = Call->_get_current_call();
	croak "Can't create a Delay without a current Call" unless $call;

	my $self = bless {
		delay_id    => undef,
		owning_call => $call,
		event       => $event,
	}, $class;

	# $self is stringified here.  We'll recall the blessed version later
	# from from the weak reference held by the owning Call.
	$self->{delay_id} = $poe_kernel->delay_set(
		__stage_timer => $length, "$self", $call
	);

	$call->register_resource($self);

	# TODO - Some sort of handle should be returned, but probably not
	# the object itself.  Maybe a proxy containing a weak reference?
	# Otherwise individual resources can't be released.
	return undef;
}

sub DESTROY {
	my $self = shift;

	if ($self->{delay_id}) {
		$poe_kernel->alarm_remove(delete $self->{delay_id});
	}

	if ($self->{owning_call}) {
		(delete $self->{owning_call})->unregister_resource($self);
	}
}

1;
