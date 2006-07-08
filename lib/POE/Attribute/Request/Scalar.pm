# $Id$

=head1 NAME

POE::Attribute::Request::Scalar - access redirector for request closures

=head1 SYNOPSIS

	# This class is used internally by POE::Stage.  Nevertheless:

	tie(
		$scalar,
		"POE::Attribute::Request::Scalar",
		$current_stage,
		$request_id,
		$attribute_name
	);

=head1 DESCRIPTION

POE::Attribute::Request::Scalar implements part of the public
interface for request continuations.  When the user executes

	my $scalar :Req;

the $scalar is tied to POE::Attribute::Request::Scalar behind the
scenes.  Subsequent $scalar access is redirected by this class to the
proper closure for the current request in the current stage.  Please
see L<POE::Stage> for more details, including the full usage of
C<:Req>.

=cut

package POE::Attribute::Request::Scalar;

use warnings;
use strict;

use Scalar::Util qw(weaken);
use Carp qw(croak);

use constant ATT_STAGE    => 0;
use constant ATT_REQ_ID   => 1;
use constant ATT_FIELD    => 2;

sub TIESCALAR {
	my ($class, $stage, $req_id, $field) = @_;

	my $self = bless [
		$stage,   # ATT_STAGE
		$req_id,  # ATT_REQ_ID
		$field,   # ATT_FIELD
	], $class;

	weaken $self->[ATT_STAGE];

	return $self;
}

sub FETCH {
	my $self = shift;
	return(
		tied(%{$self->[ATT_STAGE]})->_request_context_fetch(
			$self->[ATT_REQ_ID], $self->[ATT_FIELD]
		)
	);
}

sub STORE {
	my ($self, $value) = @_;
	return(
		tied(%{$self->[ATT_STAGE]})->_request_context_store(
			$self->[ATT_REQ_ID], $self->[ATT_FIELD], $value
		)
	);
}

1;

=head1 BUGS

See L<http://thirdlobe.com/projects/poe-stage/report/1> for known
issues.  See L<http://thirdlobe.com/projects/poe-stage/newticket> to
report an issue.

=head1 SEE ALSO

L<POE::Stage>, L<POE>, L<http://thirdlobe.com/projects/poe-stage/>.

=head1 AUTHORS

Rocco Caputo <rcaputo@cpan.org>.

=head1 LICENSE

POE::Attribute::Request::Scalar is Copyright 2005,2006 by Rocco
Caputo.  All rights are reserved.  You may use, modify, and/or
distribute this module under the same terms as Perl itself.

=cut
