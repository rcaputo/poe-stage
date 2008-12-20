#!/sw/bin/env perl
# $Id$

# Small prototype of a Moose-based POE::Stage.  It is functional but
# not functionally complete.  It doesn't represent any features from
# POE::Stage.  It's hoped that this may become the new interface and
# framework for POE::Stage's next overhaul, but there are no
# guarantees.

{

    package Namespace;    # in Erlang and Scala this is a Node
    use Moose;

    # TODO - Global registry of objects and their roles.
    # May be distributed across a network.
    # Message routing will be determined here.

    has space => (
        is  => 'rw',
        isa => 'HashRef[Object]',
    );
}

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

    has sender => (
        is  => 'ro',
        isa => 'Str',
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

    has pid => (
        isa     => 'Str',
        is      => 'ro',
        default => sub { time },    # this should be a UID
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
            push  => 'send',
        }
    );

}

{

    # I think that the Dispatcher and the Namespace can be unified
    package Dispatcher;
    use Moose;
    use List::Util qw(sum);
    
    has actors => (
        isa       => 'HashRef[Actor]',
        is        => 'ro',
        default   => sub { {} },
        metaclass => 'Collection::Hash',
        provides  => {
            get    => 'get_actor_by_pid',
            values => 'list_actors',
        },
    );

    sub add_actor {
        my ( $self, $actor ) = @_;
        $self->actors->{ $actor->pid } = $actor;
    }

    sub pending_messages {
        my ($self) = @_;
        sum map { $_->message_count } $self->list_actors;
    }

    sub run {
        my $self = shift;

        # This while loop should be replaced by a POE run loop

        while ( $self->pending_messages ) {
            for my $actor ( $self->list_actors ) {
                next unless $actor->message_count;

                my $next_message = $actor->next_message;
                my $message_type = $next_message->type();

                # TODO - Translate the message type into a method.  For now
                # we're asuming the message type is a method name.  Later we
                # should consult the target object for a type/method mapping.

                $next_message->context( $next_message->target_context() );
                $actor->$message_type($next_message);
                $next_message->context( $next_message->sender_context() );
            }
        }
    }

    sub send {
        my ( $self, $pid, $message ) = @_;
        $message->dispatcher($self);
        $self->get_actor_by_pid($pid)->send($message);
    }
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
            $self->send($message);
            return;
        }

        $self->send(
            Call->new(
                {
                    type => "say_goodbye",
                    args => $message->args,
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
    my $dispatcher = Dispatcher->new();
    my $app        = App->new();

    $dispatcher->add_actor($app);

    $app->send(
        Call->new(
            {
                type => "say_hello",
                args => { whom => "world", count => 0 },
            },
        )
    );

    $dispatcher->run();
    exit;
}
