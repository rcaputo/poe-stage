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
	croak "$class requires a '_length'" unless defined $length;

	my $method = delete $args{_method};
	croak "$class requires an '_method'" unless defined $method;

	my $request = POE::Request->_get_current_request();
	croak "Can't create a $class without an active request" unless $request;

	# Wrap a weak copy of the request reference in a strong envelope so
	# it can be passed around.

	my $req_envelope = [ $request ];
	weaken $req_envelope->[0];

	my $self = bless {
		request   => $req_envelope,
		method    => $method,
		args      => \%args,
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

# Resource delivery is like a response.

sub deliver {
	my ($self, %args) = @_;

	# Open the envelope.
	my $request = $self->{request}[0];
	$request->redeliver($self->{method});
}

1;
