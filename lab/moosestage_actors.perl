#!/sw/bin/env perl
# $Id$

# Small prototype of a Moose-based POE::Stage.  It is functional but
# not functionally complete.  It doesn't represent any features from
# POE::Stage.  It's hoped that this may become the new interface and
# framework for POE::Stage's next overhaul, but there are no
# guarantees.

{

    package Call;    # a Message between Actors
    use Moose;

    has type => (
        is  => 'rw',
        isa => 'Str',
    );

    has args => (
        is  => 'ro',
        isa => 'HashRef[Any]',
    );

    has [qw(target sender)] => (    # actor id's
        isa => 'Str',
        is  => 'rw',
    );

    has context => (
        is  => 'rw',
        isa => 'HashRef[Any]',
    );

    has dispatcher => (
        is  => 'rw',
        isa => 'Dispatcher',
    );

    # TODO - Sender and target contexts should not be coupled to the
    # request.  Passing a request should not involve copying (or
    # serializing and transmitting) data the target will never see.
    #
    # A better mechanism would be to keep the sender context in the
    # reqest, but strip it from the copy transmitted down the wire.
    #
    # On the receiving end, the target can initialize its context before
    # initial dispatch.

    has sender_context => (
        is      => 'rw',
        isa     => 'HashRef[Any]',
        default => sub { {} },
    );

    has target_context => (
        is      => 'rw',
        isa     => 'HashRef[Any]',
        default => sub { {} },
    );
}

{

    package Actor;
    use Moose;
    use MooseX::AttributeHelpers;

    has id => (
        isa     => 'Str',
        is      => 'ro',
        default => sub {
            join(" ", $$, time(), times())
        }, # this should be a UID
    );

    has namespace => (
        isa     => 'Namespace',
        is      => 'rw',
        weaken  => 1,
        handles => [qw(send)],
    );

    has mailbox => (
        is        => 'rw',
        isa       => 'ArrayRef[Call]',
        default   => sub { [] },
        metaclass => 'Collection::Array',
        provides  => {
            empty => 'mailbox_empty',
            count => 'message_count',
            shift => 'next_message',
            push  => 'receive',
        }
    );

}

{

    # I think that the Dispatcher and the Namespace can be unified
    package Dispatcher;
    use Moose;
    use List::Util qw(sum);

    has namespace => (
        isa      => 'Namespace',
        is       => 'ro',
        weaken   => 1,
        required => 1,
        handles  => [qw(list_actors get_actor_by_id)],
    );

    sub pending_messages { # dngor figured out to optimize the messages
        my ($self) = $_[0];
        map { $_->next_message || () } $self->list_actors;    
    }

    sub run {
        my $self = shift;

        # This while loop should be replaced by a POE run loop

        while ( my @messages = $self->pending_messages ) {
            for my $message (@messages) {
                last unless defined $message;
                my $actor        = $self->get_actor_by_id( $message->target );
                my $message_type = $message->type();

                # TODO - Translate the message type into a method.  For now
                # we're asuming the message type is a method name.  Later we
                # should consult the target object for a type/method mapping.

                $message->context( $message->target_context() );
                $actor->$message_type($message);
                $message->context( $message->sender_context() );
            }
        }
    }

    sub send {
        my ( $self, $id, $message ) = @_;
        $message->dispatcher($self);
        $self->get_actor_by_id($id)->send($message);
    }
}

{

    package Namespace;    # in Erlang and Scala this is a Node
    use Moose;

    # TODO - Global registry of objects and their roles.
    # May be distributed across a network.
    # Message routing will be determined here.

    has space => (        # other namespaces
        is  => 'rw',
        isa => 'HashRef[Object]',
    );

    has actors => (       # actors in this namespace
        isa       => 'HashRef[Actor]',
        is        => 'ro',
        default   => sub { {} },
        metaclass => 'Collection::Hash',
        provides  => {
            get    => 'get_actor_by_id',
            values => 'list_actors',
        },
    );

    sub add_actor {
        my ( $self, $actor ) = @_;
        $actor->namespace($self);
        $self->actors->{ $actor->id } = $actor;
    }

    sub send {
        my ( $self, $message ) = @_;
        $self->get_actor_by_id( $message->target )->receive($message);
    }

    has dispatcher => (
        isa        => 'Dispatcher',
        is         => 'ro',
        lazy_build => 1,
        handles    => [qw(run)],
    );

    sub _build_dispatcher { Dispatcher->new( namespace => $_[0] ) }
}

{

    package App;
    use Moose;
    extends qw(Actor);

    sub say_hello {
        my ( $self, $message ) = @_;
        my $whom  = $message->args->{whom};
        my $count = ++$message->context->{count};

        print "hello, $whom! ($count)\n";

        if ( $count < 9 ) {
            $message->sender( $self->id );
            $self->send($message);
            return;
        }

        $self->send(
            Call->new(
                {
                    sender => $self->id,
                    target => $message->sender,
                    type   => "say_goodbye",
                    args   => $message->args,
                },
            )
        );
    }

    sub say_goodbye {
        my ( $self, $message ) = @_;
        my $whom = $message->args->{whom};

        print "goodbye, $whom!\n";
    }
}

{

    package main;
    my $namespace = Namespace->new();
    my $app       = App->new();

    $namespace->add_actor($app);

    $namespace->send(
        Call->new(
            {
                target => $app->id,
                type   => "say_hello",
                args   => { whom => "world", count => 0 },
            },
        )
    );

    $namespace->run();
    exit;
}

# Rocco uses tabs by default.  This sets his editor to follow the
# author's personal style.
# vim: ts=4 sw=4 expandtab
