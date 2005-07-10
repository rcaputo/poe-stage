# $Id$

# Internal request class that is used for $request->return().  It
# subclasses POE::Request::Upward, customizing certain methods and
# tweaking instantiation where necessary.

package POE::Request::Return;

use warnings;
use strict;

use POE::Request::Upward qw(
	REQ_PARENT_REQUEST
	REQ_DELIVERY_RSP
);

use base qw(POE::Request::Upward);

# Return requests are defunct.  They may not be recalled.  Even though
# the parent will never be used here, it's important not to store it
# anyway.  Otherwise circular references may occur, or deeeeep
# recursion in cases where recursion isn't necessary at all.

sub _init_subclass {
	my ($self, $current_request) = @_;
	my $self_data = tied(%$self);
	$self_data->[REQ_PARENT_REQUEST] = 0;
	$self_data->[REQ_DELIVERY_RSP]   = 0;
}

1;
