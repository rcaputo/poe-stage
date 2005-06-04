# $Id$

# A simple watcher that looks for input on a filehandle.

package POE::Watcher::Input;

use warnings;
use strict;

use Scalar::Util qw(weaken);
use Carp qw(croak);
use POE::Kernel;

sub new {
	my ($class, %args) = @_;

	my $handle = delete $args{_handle};
	croak "$class requires a '_handle'" unless defined $handle;

	my $input_method = delete $args{_on_input};
	croak "$class requires an '_on_input'" unless defined $input_method;

	my $request = POE::Request->_get_current_request();
	croak "Can't create a $class without an active request" unless $request;

	# TODO - Make sure no other adorned arguments exist.

	# Wrap a weak copy of the request reference in a strong envelope so
	# it can be passed around.

	my $req_envelope = [ $request ];
	weaken $req_envelope->[0];

	my $self = bless {
		request   => $req_envelope,
		on_input  => $input_method,
		handle    => $handle,
		args      => \%args,
	}, $class;

	# Wrap a weak $self in a strong envelope for passing around.

	my $self_envelope = [ $self ];
	weaken $self_envelope->[0];

	$poe_kernel->select_read($handle, "stage_io", $self_envelope);

	# Owner gets a strong reference.
	return $self;
}

sub DESTROY {
	my $self = shift;

	if (exists $self->{handle}) {
		$poe_kernel->select_read(delete($self->{handle}), undef);
	}
}

# Resource delivery redelivers the request the resource was created
# in, but to a new method.

sub deliver {
	my ($self, %args) = @_;

	# Open the envelope.
	my $request = $self->{request}[0];
	$request->deliver($self->{on_input});
}

1;
