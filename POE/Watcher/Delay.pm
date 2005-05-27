# $Id$

# A simple Delay class.
#
# This is a first stab at the third version of POE::Watcher::Delay.
# TODO - Abstract a lot of the details into a base POE::Watcher class.

package POE::Watcher::Delay;

use warnings;
use strict;

use Scalar::Util qw(weaken);
use Carp qw(croak);
use POE::Kernel;

sub new {
	my ($class, %args) = @_;

	my $length = delete $args{_length};
	croak "$class requires a '_length' parameter" unless defined $length;

	my $on_success = delete $args{_on_success};
	croak "$class requires an '_on_success' method" unless defined $on_success;

	my $request = POE::Request->_get_current_request();
	croak "Can't create a $class without an active request" unless $request;

	# Wrap a weak copy of the request reference in a strong envelope so
	# it can be passed around.

	my $req_envelope = [ $request ];
	weaken $req_envelope->[0];

	my $self = bless {
		request     => $req_envelope,
		on_success  => $on_success,
		args        => \%args,
	}, $class;

	# Post out a timer.
	# Wrap a weak $self in a strong envelope for passing around.

	my $self_envelope = [ $self ];
	weaken $self_envelope->[0];

	$self->{delay_id} = $poe_kernel->delay_set(
		stage_timer => $length, $self_envelope
	);

	# Owner gets a strong reference.
	return $self;
}

sub DESTROY {
	my $self = shift;

	if (exists $self->{delay_id}) {
		$poe_kernel->alarm_remove(delete $self->{delay_id});
	}
}

# Resource delivery redelivers the request the resource was created
# in, but to a new method.

sub deliver {
	my ($self, %args) = @_;

	# Open the envelope.
	my $request = $self->{request}[0];
	$request->redeliver($self->{on_success});
}

1;
