package Object;

use Moose;

use Scalar::Util qw(weaken blessed);
use Carp qw(croak);

use Hash::Util qw(fieldhash);
use Hash::Util::FieldHash qw(id);
fieldhash my %parents;
fieldhash my %children;

# Singleton POE::Session.

sub POE::Kernel::ASSERT_DEFAULT () { 1 }
use POE;

POE::Kernel->run(); # disables a warning

my $singleton_session_id = POE::Session->create(
	inline_states => {
		# Make the session conveniently accessible.
		# Although we're using the $singleton_session_id, so why bother?

		_start => sub {
			$_[KERNEL]->alias_set(__PACKAGE__);
		},

		# Handle a timer.  Deliver it to its resource.
		# $resource is an envelope around a weak POE::Watcher reference.

		set_timer => sub {
			my ($interval, $object) = @_[ARG0, ARG1];

			my $envelope = [ $object ];
			weaken $envelope->[0];

			return $POE::Kernel::poe_kernel->delay_set(
				'timer',
				$interval,
				$envelope,
			);
		},

		timer => sub {
			my $resource = $_[ARG0];
			eval { $resource->[0]->_deliver(); };
			die if $@;
		},
	},
)->ID();

has session_id => (
	isa => 'Str',
	is => 'ro',
	default => $singleton_session_id,
);

# Base class.

sub BUILD {
	my ($self, $params) = @_;

	my $parent;
	{
		package DB;
		use Scalar::Util qw(blessed);

		# Walk the call stack out of Moose.
		my $i = 1;
		$i++ while (
			(caller($i))[0] =~ /^(Moose::Object|Class::MOP)/
		);
		$i++;

		my @dummy = caller($i);
		$parent = $DB::args[0];
		$parent = (caller($i-1))[0] unless blessed($parent);
	}
	die unless defined $parent;

	# Register the parent/child relationship.

	$parents{$self} = $parent;
	weaken $parents{$self} if blessed $parent;

	$children{$parent}{$self} = $self;
	weaken $children{$parent}{$self};
}

sub parent {
	my $self = shift;
	return unless exists $parents{$self};
	return $parents{$self};
}

sub _deliver {
	die "@_";
}

sub manage {
	my ($self, $sub_object) = @_;
	croak "cannot manage an object we didn't create" unless (
		exists $children{$self}{$sub_object}
	);

	# TODO - We could warn about redundant calls if the stored child
	# isn't currently weak.

	# Store a strong copy.
	$children{$self}{$sub_object} = $sub_object;
}

sub abandon {
	my ($self, $sub_object) = @_;
	croak "cannot manage an object we didn't create" unless (
		exists $children{$self}{$sub_object}
	);

	# TODO - We could warn about redundant calls if the stored child
	# already is weak.
	weaken $children{$self}{$sub_object};
}

sub spawn {
	my ($class, @args) = @_;
	my $self = $class->new(@args);
	$parents{$self}->manage($self);
}

# TODO - Filter by class.
# TODO - Filter by role.
sub children {
	my $self = shift;
	return values %{$children{$self}};
}

1;
