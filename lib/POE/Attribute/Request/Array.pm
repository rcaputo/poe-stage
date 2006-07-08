# $Id$

=head1 NAME

POE::Attribute::Request::Array - access redirector for request closures

=head1 SYNOPSIS

	# This class is used internally by POE::Stage.  Nevertheless:

	tie(
		@array,
		"POE::Attribute::Request::Array",
		$current_stage,
		$request_id,
		$attribute_name
	);

=head1 DESCRIPTION

POE::Attribute::Request::Array implements part of the public interface
for request continuations.  When the user executes

	my @array :Req;

the @array is tied to POE::Attribute::Request::Array behind the
scenes.  Subsequent @array access is redirected by this class to the
proper closure for the current request in the current stage.  Please
see L<POE::Stage> for more details, including the full usage of
C<:Req>.

=cut

package POE::Attribute::Request::Array;

use warnings;
use strict;

use Scalar::Util qw(weaken);
use Carp qw(croak);

use constant ATT_STAGE    => 0;
use constant ATT_REQ_ID   => 1;
use constant ATT_FIELD    => 2;

sub TIEARRAY {
	my ($class, $stage, $req_id, $field) = @_;

	my $self = bless [
		$stage,   # ATT_STAGE
		$req_id,  # ATT_REQ_ID
		$field,   # ATT_FIELD
	], $class;

	weaken $self->[ATT_STAGE];

	# Ensure an arrayref exists in this context slot.
	unless(tied(%$stage)->_request_context_fetch($req_id, $field)) {
		tied(%$stage)->_request_context_store($req_id, $field, [ ]);
	}

	return $self;
}

sub FETCH {
	my ($self, $index) = @_;
	my $ref = tied(%{$self->[ATT_STAGE]})->_request_context_fetch(
		$self->[ATT_REQ_ID], $self->[ATT_FIELD]
	);
	return $ref->[$index];
}

sub STORE {
	my ($self, $index, $value) = @_;
	my $ref = tied(%{$self->[ATT_STAGE]})->_request_context_fetch(
		$self->[ATT_REQ_ID], $self->[ATT_FIELD]
	);
	return $ref->[$index] = $value;
}

sub FETCHSIZE {
	my ($self) = @_;
	my $ref = tied(%{$self->[ATT_STAGE]})->_request_context_fetch(
		$self->[ATT_REQ_ID], $self->[ATT_FIELD]
	);
	return scalar @$ref;
}

sub STORESIZE {
	my ($self, $size) = @_;
	my $ref = tied(%{$self->[ATT_STAGE]})->_request_context_fetch(
		$self->[ATT_REQ_ID], $self->[ATT_FIELD]
	);
	return $#{$ref} = $size - 1;
}

sub CLEAR {
	my ($self) = @_;
	my $ref = tied(%{$self->[ATT_STAGE]})->_request_context_fetch(
		$self->[ATT_REQ_ID], $self->[ATT_FIELD]
	);
	return @$ref = ();
}

sub POP {
	my ($self) = @_;
	my $ref = tied(%{$self->[ATT_STAGE]})->_request_context_fetch(
		$self->[ATT_REQ_ID], $self->[ATT_FIELD]
	);
	return pop @$ref;
}

sub PUSH {
	my $self = shift;
	my $ref = tied(%{$self->[ATT_STAGE]})->_request_context_fetch(
		$self->[ATT_REQ_ID], $self->[ATT_FIELD]
	);
	return push @$self, @_;
}

sub SHIFT {
	my ($self) = @_;
	my $ref = tied(%{$self->[ATT_STAGE]})->_request_context_fetch(
		$self->[ATT_REQ_ID], $self->[ATT_FIELD]
	);
	return shift @$ref;
}

sub UNSHIFT {
	my $self = shift;
	my $ref = tied(%{$self->[ATT_STAGE]})->_request_context_fetch(
		$self->[ATT_REQ_ID], $self->[ATT_FIELD]
	);
	return unshift @$ref, @_;
}

sub EXISTS {
	my ($self, $index) = @_;
	my $ref = tied(%{$self->[ATT_STAGE]})->_request_context_fetch(
		$self->[ATT_REQ_ID], $self->[ATT_FIELD]
	);
	return exists $ref->[$index];
}

sub DELETE {
	my ($self, $index) = @_;
	my $ref = tied(%{$self->[ATT_STAGE]})->_request_context_fetch(
		$self->[ATT_REQ_ID], $self->[ATT_FIELD]
	);
	return delete $ref->[$index];
}

sub SPLICE {
	my $self = shift;
	my $offset = @_ ? shift : 0;

	my $ref = tied(%{$self->[ATT_STAGE]})->_request_context_fetch(
		$self->[ATT_REQ_ID], $self->[ATT_FIELD]
	);

	$offset += @$ref if $offset < 0;
	my $length = @_ ? shift : @$ref - $offset;
	return splice @$ref, $offset, $length, @_;
}

sub EXTEND { }

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

POE::Attribute::Request::Array is Copyright 2005,2006 by Rocco Caputo.
All rights are reserved.  You may use, modify, and/or distribute this
module under the same terms as Perl itself.

=cut
