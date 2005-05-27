# $Id$

# A DNS resolver stage for testing poecall in "real world" situations.

package Stage::DNS;

use warnings;
use strict;

use Stage;

use vars qw($VERSION);
$VERSION = '0.98';

use Carp qw(croak);

use Socket qw(unpack_sockaddr_in inet_ntoa);
use Net::DNS;

# Object fields.  "SF" stands for "self".

sub SF_ALIAS       () { 0 }
sub SF_TIMEOUT     () { 1 }
sub SF_NAMESERVERS () { 2 }
sub SF_RESOLVER    () { 3 }

# Attempt to figure out where /etc/hosts lives.  It moves!  Augh!  It
# moves!  This is an attempt to resolve rt.cpan.org ticket #7911.

BEGIN {
  my @candidates = (
    "/etc/hosts",
  );

  if ($^O eq "MSWin32" or $^O eq "Cygwin") {
    my $sys_dir;
    $sys_dir = $ENV{SystemRoot} || "c:\\Windows";
    push(
      @candidates,
      "$sys_dir\\System32\\Drivers\\Etc\\hosts",
      "$sys_dir\\System\\Drivers\\Etc\\hosts",
      "$sys_dir\\hosts",
    );
  }

  my $host_file = $candidates[0];
  foreach my $candidate (@candidates) {
    next unless -f $candidate;
    $host_file = $candidate;
    last;
  }

  $host_file =~ s/\\+/\//g;

  eval "sub ETC_HOSTS () { '$host_file' }";
  die if $@;
}

# Spawn a new PoCo::Client::DNS session.  This basically is a
# constructor, but it isn't named "new" because it doesn't create a
# usable object.  Instead, it spawns the object off as a session.

sub spawn {
  my $type = shift;
  croak "$type requires an even number of parameters" if @_ % 2;
  my %params = @_;

  my $alias = delete $params{Alias};
  $alias = "resolver" unless $alias;

  my $timeout = delete $params{Timeout};
  $timeout = 90 unless $timeout;

  my $nameservers = delete $params{Nameservers};

  croak(
    "$type doesn't know these parameters: ", join(', ', sort keys %params)
  ) if scalar keys %params;

  my $self = bless [
    $alias,                     # SF_ALIAS
    $timeout,                   # SF_TIMEOUT
    $nameservers,               # SF_NAMESERVERS
    Net::DNS::Resolver->new(),  # SF_RESOLVER
  ], $type;

  # Set the list of nameservers, if one was supplied.
  if (defined($nameservers) and ref($nameservers) eq 'ARRAY') {
    $self->[SF_RESOLVER]->nameservers(@$nameservers);
  }

  POE::Session->create(
    object_states => [
      $self => {
        _default         => "_dns_default",
        _start           => "_dns_start",
        got_dns_response => "_dns_response",
        resolve          => "_dns_resolve",
        send_request     => "_dns_do_request",
      },
    ],
  );

  return $self;
}

# Public method interface.

sub resolve {
  my $self = shift;
  croak "resolve() needs an even number of parameters" if @_ % 2;
  my %args = @_;

  croak "resolve() must include an 'event'"  unless exists $args{event};
  croak "resolve() must include a 'context'" unless exists $args{context};
  croak "resolve() must include a 'host'"    unless exists $args{host};

  $poe_kernel->post( $self->[SF_ALIAS], "resolve", \%args );

  return undef;
}

# Start the resolver session.  Record the parameters which were
# validated in spawn(), create the internal resolver object, and set
# an alias which we'll be known by.

sub _dns_start {
  my ($object, $kernel) = @_[OBJECT, KERNEL];
  $kernel->alias_set($object->[SF_ALIAS]);
}

# Receive a request.  Version 4 API.  This uses extra reference counts
# to keep the client sessions alive until responses are ready.

sub _dns_resolve {
  my ($self, $kernel, $sender, $event, $host, $type, $class) =
    @_[OBJECT, KERNEL, SENDER, ARG0, ARG1, ARG2, ARG3];

  my $debug_info =
    "in Client::DNS request at $_[CALLER_FILE] line $_[CALLER_LINE]\n";

  my ($api_version, $context, $timeout);

  # Version 3 API.  Pass the entire request as a hash.
  if (ref($event) eq 'HASH') {
    my %args = %$event;

    $type = delete $args{type};
    $type = "A" unless $type;

    $class = delete $args{class};
    $class = "IN" unless $class;

    $event = delete $args{event};
    die "Must include an 'event' $debug_info" unless $event;

    $context = delete $args{context};
    die "Must include a 'context' $debug_info" unless $context;

    $timeout = delete $args{timeout};

    $host = delete $args{host};
    die "Must include a 'host' $debug_info" unless $host;

    $api_version = 3;
  }

  # Parse user args from the magical $response format.  Version 2 API.

  elsif (ref($event) eq "ARRAY") {
    $context     = $event;
    $event       = shift @$context;
    $api_version = 2;
  }

  # Whee.  Version 1 API.

  else {
    $context     = [ ];
    $api_version = 1;
  }

  # Default the request's timeout.
  $timeout = $self->[SF_TIMEOUT] unless $timeout;

  # Set an extra reference on the sender so it doesn't go away.
  $kernel->refcount_increment($sender->ID, __PACKAGE__);

  # If it's an IN type A request, check /etc/hosts or the equivalent.
  # -><- This is not always the right thing to do, but it's more right
  # more often than never checking at all.

  if ($type eq "A" and $class eq "IN") {
    if (open(HOST, "<", ETC_HOSTS)) {
      while (<HOST>) {
        next if /^\s*\#/;
        s/^\s*//;
        chomp;
        my ($address, @aliases) = split;
        next unless grep /^\Q$host\E$/i, @aliases;
        close HOST;

        # Pretend the request went through a name server.

        my $packet = Net::DNS::Packet->new($address, "A", "IN");
        $packet->push(
          "answer",
          Net::DNS::RR->new(
            Name    => $host,
            TTL     => 1,
            Class   => $class,
            Type    => $type,
            Address => $address,
          )
        );

        # Send the response immediately, and return.

        _send_response(
          api_ver  => $api_version,
          sender   => $sender,
          event    => $event,
          host     => $host,
          type     => $type,
          class    => $class,
          context  => $context,
          response => $packet,
          error    => "",
        );

        close HOST;
        return;
      }
      close HOST;
    }
  }

  # We are here.  Yield off to the state where the request will be
  # sent.  This is done so that the do-it state can yield or delay
  # back to itself for retrying.

  my $now = time();
  $kernel->yield(
    send_request => {
      sender    => $sender,
      event     => $event,
      host      => $host,
      type      => $type,
      class     => $class,
      context   => $context,
      started   => $now,
      ends      => $now + $timeout,
      api_ver   => $api_version,
    }
  );
}

# Perform the real request.  May recurse to perform retries.

sub _dns_do_request {
  my ($self, $kernel, $req) = @_[OBJECT, KERNEL, ARG0];

  # Did the request time out?
  my $remaining = $req->{ends} - time();
  if ($remaining <= 0) {
    _send_response(
      %$req,
      response => undef,
      error    => "timeout",
    );
    return;
  }

  # Send the request.
  my $resolver_socket = $self->[SF_RESOLVER]->bgsend(
    $req->{host},
    $req->{type},
    $req->{class}
  );

  # The request failed?  Attempt to retry.

  unless ($resolver_socket) {
    $remaining = 1 if $remaining > 1;
    $kernel->delay_add(send_request => $remaining, $req);
    return;
  }

  # Set a timeout for the request, and watch the response socket for
  # activity.

  $req_by_socket{$resolver_socket} = $req;

  $kernel->delay($resolver_socket, $remaining, $resolver_socket);
  $kernel->select_read($resolver_socket, 'got_dns_response');
}

# A resolver query timed out.  Post an error back.

sub _dns_default {
  my ($kernel, $event, $args) = @_[KERNEL, ARG0, ARG1];
  my $socket = $args->[0];

  return unless defined($socket) and $event eq $socket;

  my $req = delete $req_by_socket{$socket};
  return unless $req;

  # Stop watching the socket.
  $kernel->select_read($socket);

  # Post back an undefined response, indicating we timed out.
  _send_response(
    %$req,
    response => undef,
    error    => "timeout",
  );

  # Don't accidentally handle signals.
  return;
}

# A resolver query generated a response.  Post the reply back.

sub _dns_response {
  my ($self, $kernel, $socket) = @_[OBJECT, KERNEL, ARG0];

  my $req = delete $req_by_socket{$socket};
  return unless $req;

  # Turn off the timeout for this request, and stop watching the
  # resolver connection.
  $kernel->delay($socket);
  $kernel->select_read($socket);

  # Read the DNS response.
  my $packet = $self->[SF_RESOLVER]->bgread($socket);

  # Set the packet's answerfrom field, if the packet was received ok
  # and an answerfrom isn't already included.  This uses the
  # documented peerhost() method

  if (defined $packet and !defined $packet->answerfrom) {
    my $answerfrom = getpeername($socket);
    if (defined $answerfrom) {
      $answerfrom = (unpack_sockaddr_in($answerfrom))[1];
      $answerfrom = inet_ntoa($answerfrom);
      $packet->answerfrom($answerfrom);
    }
  }

  # Send the response.
  _send_response(
    %$req,
    response => $packet,
    error    => $self->[SF_RESOLVER]->errorstring(),
  );
}

# Send a response.  Fake a postback for older API versions.  Send a
# nice, tidy hash for new ones.  Also decrement the reference count
# that's keeping the requester session alive.

sub _send_response {
  my %args = @_;

  # Simulate a postback for older API versions.

  my $api_version = delete $args{api_ver};
  if ($api_version < 3) {
    $poe_kernel->post(
      $args{sender}, $args{event},
      [ $args{host}, $args{type}, $args{class}, @{$args{context}} ],
      [ $args{response}, $args{error} ],
    );
  }

  # New, fancy, shiny hash-based response.

  else {
    $poe_kernel->post(
      $args{sender}, $args{event},
      {
        host     => $args{host},
        type     => $args{type},
        class    => $args{class},
        context  => $args{context},
        response => $args{response},
        error    => $args{error},
      }
    );
  }

  # Let the client session go.
  $poe_kernel->refcount_decrement($args{sender}->ID, __PACKAGE__);
}

1;

__END__

=head1 NAME

POE::Component::Client::DNS - non-blocking, concurrent DNS requests

=head1 SYNOPSIS

  use POE qw(Component::Client::DNS);

  my $named = POE::Component::Client::DNS->spawn(
    Alias => "named"
  );

  POE::Session->create(
    inline_states  => {
      _start   => \&start_tests,
      response => \&got_response,
    }
  );

  POE::Kernel->run();
  exit;

  sub start_tests {
    my $response = $named->resolve(
      event   => "response",
      host    => "localhost",
      context => { },
    );
    if ($response) {
      $_[KERNEL]->yield(response => $response);
    }
  }

  sub got_response {
    my $response = $_[ARG0];
    my @answers = $response->{response}->answer();

    foreach my $answer (@answers) {
      print(
        "$response->{host} = ",
        $answer->type(), " ",
        $answer->rdatastr(), "\n"
      );
    }
  }

=head1 DESCRIPTION

POE::Component::Client::DNS provides a facility for non-blocking,
concurrent DNS requests.  Using POE, it allows other tasks to run
while waiting for name servers to respond.

=head1 PUBLIC METHODS

=over 2

=item spawn

A program must spawn at least one POE::Component::Client::DNS instance
before it can perform background DNS lookups.  Each instance
represents a connection to a name server, or a pool of them.  If a
program only needs to request DNS lookups from one server, then you
only need one POE::Component::Client::DNS instance.

As of version 0.98 you can override the default timeout per request.
From this point forward there is no need to spawn multiple instances o
affect different timeouts for each request.

PoCo::Client::DNS's C<spawn> method takes a few named parameters:

Alias sets the component's alias.  Requests will be posted to this
alias.  The component's alias defaults to "resolver" if one is not
provided.  Programs spawning more than one DNS client component must
specify aliases for N-1 of them, otherwise alias collisions will
occur.

  Alias => $session_alias,  # defaults to "resolver"

Timeout sets the component's default timeout.  The timeout may be
overridden per request.  See the "request" event, later on.  If no
Timeout is set, the component will wait 90 seconds per request by
default.

Timeouts may be set to real numbers.  Timeouts are more accurate if
you have Time::HiRes installed.  POE (and thus this component) will
use Time::HiRes automatically if it's available.

  Timeout => $seconds_to_wait,  # defaults to 90

Nameservers holds a reference to a list of name servers to try.  The
list is passed directly to Net::DNS::Resolver's nameservers() method.
By default, POE::Component::Client::DNS will query the name servers
that appear in /etc/resolv.conf or its equivalent.

  Nameservers => \@name_servers,  # defaults to /etc/resolv.conf's

=item resolve

resolve() requests the component to resolve a host name.  It will
return a hash reference (described in RESPONSE MESSAGES, below) if it
can honor the request immediately (perhaps from a cache).  Otherwise
it returns undef if a resolver must be consulted asynchronously.

Requests are passed as a list of named fields.

  $resolver->resolve(
    class   => $dns_record_class,  # defaults to "IN"
    type    => $dns_record_type,   # defaults to "A"
    host    => $request_host,      # required
    context => $request_context,   # required
    event   => $response_event,    # required
    timeout => $request_timeout,   # defaults to spawn()'s Timeout
  );

The "class" and "type" fields specify what kind of information to
return about a host.  Most of the time internet addresses are
requested for host names, so the class and type default to "IN"
(internet) and "A" (address), respectively.

The "host" field designates the host to look up.  It is required.

The "event" field tells the component which event to send back when a
response is available.  It is required, but it will not be used if
resolve() can immediately return a cached response.

"timeout" tells the component how long to wait for a response to this
request.  It defaults to the "Timeout" given at spawn() time.

"context" includes some external data that links responses back to
their requests.  The context data is provided by the program that uses
POE::Component::Client::DNS.  The component will pass the context back
to the program without modification.  The "context" parameter is
required, and may contain anything that fits in a scalar.

=head1 RESPONSE MESSAGES

POE::Component::Client::DNS responds in one of two ways.  Its
resolve() method will return a response immediately if it can be found
in the component's cache.  Otherwise the component posts the response
back in $_[ARG0].  In either case, the response is a hash reference
containing the same fields:

  host     => $request_host,
  type     => $request_type,
  class    => $request_class,
  context  => $request_context,
  response => $net_dns_packet,
  error    => $net_dns_error,

The "host", "type", "class", and "context" response fields are
identical to those given in the request message.

"response" contains a Net::DNS::Packet object on success or undef if
the lookup failed.  The Net::DNS::Packet object describes the response
to the program's request.  It may contain several DNS records.  Please
consult L<Net::DNS> and L<Net::DNS::Packet> for more information.

"error" contains a description of any error that has occurred.  It is
only valid if "response" is undefined.

=head1 SEE ALSO

L<POE> - POE::Component::Client::DNS builds heavily on POE.

L<Net::DNS> - This module uses Net::DNS internally.

L<Net::DNS::Packet> - Responses are returned as Net::DNS::Packet
objects.

=head1 BUGS

This component does not yet expose the full power of Net::DNS.

Timeouts have not been tested extensively.  Please contact the author
if you know of a reliable way to test DNS timeouts.

=head1 DEPRECATIONS

The older, list-based interfaces are no longer documented as of
version 0.98.  They are being phased out.  The method-based interface,
first implementedin version 0.98, will replace the deprecated
interfaces after a six-month phase-out period.

Version 0.98 was released in October of 2004.  The deprecated
interfaces will continue to work without warnings until January 2005.

As of January 2005, programs that use the deprecated interfaces will
continue to work, but they will generate mandatory warnings.  Those
warnings will persist until April 2005.

As of April 2005 the mandatory warnings will be upgraded to mandatory
errors.  Support for the deprecated interfaces will be removed
entirely.

=head1 AUTHOR & COPYRIGHTS

POE::Component::Client::DNS is Copyright 1999-2004 by Rocco Caputo.
All rights are reserved.  POE::Component::Client::DNS is free
software; you may redistribute it and/or modify it under the same
terms as Perl itself.

Postback arguments were contributed by tag.

Rocco may be contacted by e-mail via rcaputo@cpan.org.

=cut
