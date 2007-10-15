#!/usr/bin/env perl
# $Id$

# Example taken from
# http://code2.0beta.co.uk/moose/svn/MooseX-POE/trunk/ex/candygram.pl
# which is based on http://candygram.sourceforge.net/node6.html

{
	package Proc;
	use POE::Stage qw(:base req);

	sub on_knock {
		my ($self, $req, $arg_name);
		print "Heard knock from $arg_name\n";
		if ($arg_name eq "candygram") {
			$self->open_door({ name => $arg_name });
		}
		else {
			$self->close_door({ name => $arg_name });
		}
	}

	sub open_door :Handler {
		my $arg_name;
		print "Opening door for $arg_name\n";
		my $req->return(
			type => "hello",
			args => {
				name => $arg_name,
			},
		);
	}

	sub close_door {
		my ($self, $arg) = @_;
		print "Closing door for $arg->{name}\n";
		req()->return(
			type => "go_away",
			args => {
				name => $arg->{name},
			},
		);
	}
}

{
	package App;
	use POE::Stage::App qw(:base);

	sub on_run {
		my $req_proc = Proc->new();

		my $req_ls = POE::Request->new(
			stage  => $req_proc,
			method => "knock",
			role => "knock",
			args => {
				name => "landshark"
			},
		);

		my $req_cg = POE::Request->new(
			stage  => $req_proc,
			method => "knock",
			role => "knock",
			args => {
				name => "candygram"
			},
		);
	}

	sub on_knock_hello {
		my $arg_name;
		print "$arg_name delivers candygram.\n";
	}

	sub on_knock_go_away {
		my $arg_name;
		print "$arg_name goes away\n";
	}
}

App->new()->run();

__END__

1) poerbook:~/projects/poe-stage% perl -Ilib candygram.perl
Heard knock from landshark
Closing door for landshark
Heard knock from candygram
Opening door for candygram
landshark goes away
candygram delivers candygram.

!!! callback leak: at lib/POE/Callback.pm line 321.
!!!   POE::Callback=CODE(0x1813978) = App::on_knock_hello
!!!   POE::Callback=CODE(0x1813c3c) = App::on_knock_go_away
!!!   POE::Callback=CODE(0x1813ce4) = App::on_run
!!!   POE::Callback=CODE(0x1814168) = Proc::on_knock
!!!   POE::Callback=CODE(0x1814408) = Proc::open_door
!!!   POE::Callback=CODE(0x1814684) = Proc::close_door


# This is a little test program to see if we could implement
# http://candygram.sourceforge.net/node6.html on MooseX::POE
# using MX::Poe objects (aka POE::Sessions) to replace threads

# Here is the relevant code from Canygram
#
#
# >>> import candygram as cg
# >>> import time
# >>> def proc_func():
# ...     r = cg.Receiver()
# ...     r.addHandler('land shark', shut_door, cg.Message)
# ...     r.addHandler('candygram', open_door, cg.Message)
# ...     for message in r:
# ...         print message
# ...
# >>> def shut_door(name):
# ...     return 'Go Away ' + name
# ...
# >>> def open_door(name):
# ...     return 'Hello ' + name
# ...
# >>> proc = cg.spawn(proc_func)
# >>> proc.send('land shark')
# >>> proc.send('candygram')
# >>> # Give the proc a chance to print its messages before termination:
# ... time.sleep(1)

#
# here is our version
#
sub main {

    sub proc_func {
        my $r = $_[0]->reciever;
        $r->add_handler( 'land_shark', \&shut_door );
        $r->add_handler( 'candygram',  \&open_door );
        while (<$r>) {
            print;
        }
    }

    sub shut_door {
        return 'Go away ' . $_[1];
    }

    sub open_door {
        return 'Hello ' . $_[1];
    }

    my $proc = Candygram->spawn( \&proc_func );
    $proc->send('land_shark');
    $proc->send('candygram');
    POE::Kernel->run;    # we have to run the kernel manually
    
}

# 
# Implementation
# 

{

    package Candygram;

    sub spawn {
        my ( $self, $func ) = splice @_, 0, 2;
        return Proc->new( func => $func, args => \@_ );
    }

}

#
# the Receiver object does all the real work
#

{

    package Receiver;
    use Moose;
    use overload '<>' => \&receive;

    has mailbox => (
        isa        => 'ArrayRef',
        is         => 'ro',
        auto_deref => 1,
        default    => sub { [] },
    );

    has handlers => (
        isa     => 'HashRef',
        is      => 'ro',
        default => sub { {} },
    );

    sub add_handler {
        my ( $self, $state, $code ) = @_;
        return if exists $self->handlers->{$state};
        $self->handlers->{$state} = $code;
    }

#   This could be cleaned up a bunch by MooseX::AttributeHelpers on the 
#   attributes above, but I didn't wan't to have a dependency
#   for a example script

    sub receive {
        my $self = shift;
        my ( $state, $args );
        return unless scalar @{ $self->mailbox };
        for ( 0 .. $#{ $self->mailbox } ) {
            my $state = $self->mailbox->[$_]->[0];
            next unless $state;
            next unless exists $self->handlers->{$state};
            ( $state, $args ) = @{ splice @{ $self->mailbox }, $_, 1 };
            if ( $state && $args ) {
                my $res = $self->handlers->{$state}->(@$args);
                return $res;
            }
        }
        return;
    }
}

{

    package Proc;
    use MooseX::POE;

    has func => (
        isa     => 'CodeRef',
        is      => 'ro',
        default => sub {
            sub { }
        },
    );
    has args => (
        isa        => 'ArrayRef',
        is         => 'ro',
        auto_deref => 1,
        default    => sub { [] },
    );

    has reciever => (
        is      => 'ro',
        default => sub { Receiver->new() },
    );

    sub START {
        my ($self) = @_;
        $self->yield('loop');
    }

    sub on_loop {
        my ($self) = @_;
        my $func = $self->func;
        $self->$func( $self->args );
    }

    sub send {
        my ( $self, $message ) = @_;
        push @{ $self->reciever->mailbox }, [ $message, \@_ ];
        $self->yield('loop');
    }

}

main();

