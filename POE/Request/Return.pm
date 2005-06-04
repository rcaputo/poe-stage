# $Id$

# Internal request class that is used for $request->return().  It
# subclasses POE::Request::Upward, customizing certain methods and
# tweaking instantiation where necessary.

package POE::Request::Return;

use warnings;
use strict;
use base qw(POE::Request::Upward);

# Return requests are defunct.  They may not be recalled.  Even though
# the parent will never be used here, it's important not to store it
# anyway.  Otherwise circular references may occur, or deeeeep
# recursion in cases where recursion isn't necessary at all.

sub _init_subclass {
	my ($self, $current_request) = @_;
	$self->{_parent_request} = 0;
	$self->{_delivery_rsp}   = 0;
}

1;
