# $Id$

=head1 NAME

POE::Attribute::Request::Hash - access redirector for request closures

=head1 SYNOPSIS

	# This class is used internally by POE::Stage.  Nevertheless:

	tie(
		%hash,
		"POE::Attribute::Request::Hash",
		$current_stage,
		$request_id,
		$attribute_name
	);

=head1 DESCRIPTION

POE::Attribute::Request::Hash implements part of the public interface
for request continuations.  When the user executes

	my %hash :Req;

the %hash is tied to POE::Attribute::Request::Hash behind the scenes.
Subsequent %hash access is redirected by this class to the proper
closure for the current request in the current stage.  Please see
L<POE::Stage> for more details, including the full usage of C<:Req>.

=cut

package POE::Attribute::Request::Hash;

use warnings;
use strict;

use Scalar::Util qw(weaken);
use Carp qw(croak);

use constant ATT_STAGE    => 0;
use constant ATT_REQ_ID   => 1;
use constant ATT_FIELD    => 2;

sub TIEHASH {
	my ($class, $stage, $req_id, $field) = @_;

	my $self = bless [
		$stage,   # ATT_STAGE
		$req_id,  # ATT_REQ_ID
		$field,   # ATT_FIELD
	], $class;

	weaken $self->[ATT_STAGE];

	# Ensure an arrayref exists in this context slot.
	unless(tied(%$stage)->_request_context_fetch($req_id, $field)) {
		tied(%$stage)->_request_context_store($req_id, $field, { });
	}

	return $self;
}

sub FETCH {
	my ($self, $key) = @_;
	my $ref = tied(%{$self->[ATT_STAGE]})->_request_context_fetch(
		$self->[ATT_REQ_ID], $self->[ATT_FIELD]
	);
	return $ref->{$key};
}

sub STORE {
	my ($self, $key, $value) = @_;
	my $ref = tied(%{$self->[ATT_STAGE]})->_request_context_fetch(
		$self->[ATT_REQ_ID], $self->[ATT_FIELD]
	);
	return $ref->{$key} = $value;
}

sub DELETE {
	my ($self, $key) = @_;
	my $ref = tied(%{$self->[ATT_STAGE]})->_request_context_fetch(
		$self->[ATT_REQ_ID], $self->[ATT_FIELD]
	);
	return delete $ref->{$key};
}

sub CLEAR {
	my ($self) = @_;
	my $ref = tied(%{$self->[ATT_STAGE]})->_request_context_fetch(
		$self->[ATT_REQ_ID], $self->[ATT_FIELD]
	);
	return %$ref = ();
}

sub EXISTS {
	my ($self, $key) = @_;
	my $ref = tied(%{$self->[ATT_STAGE]})->_request_context_fetch(
		$self->[ATT_REQ_ID], $self->[ATT_FIELD]
	);
	return exists $ref->{$key};
}

sub FIRSTKEY {
	my ($self) = @_;
	my $ref = tied(%{$self->[ATT_STAGE]})->_request_context_fetch(
		$self->[ATT_REQ_ID], $self->[ATT_FIELD]
	);
	my $a = keys %$ref; # reset each() iterator
	return each %$ref;
}

sub NEXTKEY {
	my ($self, $lastkey) = @_;
	my $ref = tied(%{$self->[ATT_STAGE]})->_request_context_fetch(
		$self->[ATT_REQ_ID], $self->[ATT_FIELD]
	);
	return each %$ref;
}

sub SCALAR {
	my ($self) = @_;
	my $ref = tied(%{$self->[ATT_STAGE]})->_request_context_fetch(
		$self->[ATT_REQ_ID], $self->[ATT_FIELD]
	);
	return scalar %$ref;
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

POE::Attribute::Request::Hash is Copyright 2005,2006 by Rocco Caputo.
All rights are reserved.  You may use, modify, and/or distribute this
module under the same terms as Perl itself.

=cut
