# $Id$

package POE::Watcher;

use warnings;
use strict;

1;

=head1 NAME

POE::Watcher - a base class for POE event watchers

=head1 SYNOPSIS

	This module isn't meant to be used directly.

=head1 DESCRIPTION

POE::Watcher is a base class for POE::Stage event watchers.  It is
currently empty while the suite of event watchers builds.  Common
watcher code will eventually be hoisted into it.

POE::Watcher classes encapsulate POE::Kernel's event watchers.  They
allocate POE::Kernel watchers at creation time, and they release them
during destruction.  It is therefore important to keep references to
POE::Watcher objects until they are no longer needed.

The best place to store POE::Watcher objects is perhaps $self->{req}.
This is the scope of the current request being handled by the current
POE::Stage object.  Should the request be cancelled for some reason,
$self->{req} will go away, and so will all the watchers associated
with it.  This simplifies cleanup associated with canceled requests.

=head1 SEE ALSO

POE::Watcher subclasses may have additional features and methods.
Please see their corresponding documentation.

=head1 AUTHORS

Rocco Caputo <rcaputo@cpan.org>.

=head1 LICENSE

POE::Watcher is Copyright 2005 by Rocco Caputo.  All rights are
reserved.  You may use, modify, and/or distribute this module under
the same terms as Perl itself.

=cut
