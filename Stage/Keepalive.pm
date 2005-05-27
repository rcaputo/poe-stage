# $Id: Client-Keepalive.pm,v 1.4 2004/10/06 02:41:06 rcaputo Exp $

package POE::Component::Client::Keepalive;

use warnings;
use strict;

use vars qw($VERSION);
$VERSION = "0.01";

use Carp qw(croak);
use Errno qw(ETIMEDOUT);

use POE;
use POE::Wheel::SocketFactory;
use POE::Component::Connection::Keepalive;

use constant DEBUG => 0;

# The connection manager uses a number of data structures, most of
# them arrays.  These constants define offsets into those arrays, and
# the comments document them.

                            # @$self = (
sub SF_POOL      () { 0 }   #   \%socket_pool,
sub SF_QUEUE     () { 1 }   #   \@request_queue,
sub SF_USED      () { 2 }   #   \%sockets_in_use,
sub SF_WHEELS    () { 3 }   #   \%wheels_by_id,
sub SF_USED_EACH () { 4 }   #   \%count_by_triple,
sub SF_MAX_OPEN  () { 5 }   #   $max_open_count,
sub SF_MAX_HOST  () { 6 }   #   $max_per_host,
sub SF_SOCKETS   () { 7 }   #   \%socket_xref,
sub SF_KEEPALIVE () { 8 }   #   $keep_alive_secs,
sub SF_TIMEOUT   () { 9 }   #   $default_request_timeout,
                            # );

                            # $socket_xref{$socket} = [
sub SK_KEY       () { 0 }   #   $conn_key,
sub SK_TIMER     () { 1 }   #   $idle_timer,
                            # ];

                            # $count_by_triple{$conn_key} = # $conn_count;

                            # $wheels_by_id{$wheel_id} = [
sub WHEEL_WHEEL   () { 0 }  #   $wheel_object,
sub WHEEL_REQUEST () { 1 }  #   $request_record,
                            # ];

                            # $socket_pool{$conn_key}{$socket} = $socket;

                            # $sockets_in_use{$socket} = (
sub USED_SOCKET () { 0 }    #   $socket_handle,
sub USED_TIME   () { 1 }    #   $allocation_time,
sub USED_KEY    () { 2 }    #   $conn_key,
                            # );

                            # @request_queue = (
                            #   $request,
                            #   $request,
                            #   ....
                            # );

                            # $request = [
sub RQ_SESSION  () {  0 }   #   $request_session,
sub RQ_EVENT    () {  1 }   #   $request_event,
sub RQ_SCHEME   () {  2 }   #   $request_scheme,
sub RQ_ADDRESS  () {  3 }   #   $request_address,
sub RQ_PORT     () {  4 }   #   $request_port,
sub RQ_CONN_KEY () {  5 }   #   $request_connection_key,
sub RQ_CONTEXT  () {  6 }   #   $request_context,
sub RQ_TIMEOUT  () {  7 }   #   $request_timeout,
sub RQ_START    () {  8 }   #   $request_start_time,
sub RQ_TIMER_ID () {  9 }   #   $request_timer_id,
sub RQ_WHEEL_ID () { 10 }   #   $request_wheel_id,
                            # ];

# Create a connection manager.

sub new {
  my $class = shift;
  croak "new() needs an even number of parameters" if @_ % 2;
  my %args = @_;

  my $max_per_host = delete($args{max_per_host}) || 4;
  my $max_open     = delete($args{max_open})     || 128;
  my $keep_alive   = delete($args{keep_alive})   || 15;
  my $timeout      = delete($args{timeout})      || 120;

  my @unknown = sort keys %args;
  if (@unknown) {
    croak "new() doesn't accept: @unknown";
  }

  my $self = bless [
    { },                # SF_POOL
    [ ],                # SF_QUEUE
    { },                # SF_USED
    { },                # SF_WHEELS
    { },                # SF_USED_EACH
    $max_open,          # SF_MAX_OPEN
    $max_per_host,      # SF_MAX_HOST
    { },                # SF_SOCKETS
    $keep_alive,        # SF_KEEPALIVE
    $timeout,           # SF_TIMEOUT
  ], $class;

  POE::Session->create(
    object_states => [
      $self => {
        _start               => "_ka_initialize",
        _stop                => "_ka_ignore_this_event",
        ka_conn_failure      => "_ka_conn_failure",
        ka_conn_success      => "_ka_conn_success",
        ka_reclaim_socket    => "_ka_reclaim_socket",
        ka_relinquish_socket => "_ka_relinquish_socket",
        ka_request_timeout   => "_ka_request_timeout",
        ka_set_timeout       => "_ka_set_timeout",
        ka_shutdown          => "_ka_shutdown",
        ka_socket_activity   => "_ka_socket_activity",
        ka_keepalive_timeout => "_ka_keepalive_timeout",
        ka_wake_up           => "_ka_wake_up",
      },
    ],
  );

  return $self;
}

# Initialize the hidden session behind this component.
# Set an alias so the public methods can send it messages easily.

sub _ka_initialize {
  my ($object, $kernel) = @_[OBJECT, KERNEL];
  $kernel->alias_set("$object");
}

# Request to wake up.  This should only happen during the edge
# condition where the component's request queue goes from empty to
# having one item.
#
# It also happens during free(), to see if there are more sockets to
# deal with.
#
# TODO - Make the _ka_wake_up stuff smart enough not to post duplicate
# messages to the queue.

sub _ka_wake_up {
  my ($self, $kernel) = @_[OBJECT, KERNEL];

  # Scan the list of requests, until we find one that can be met.
  # Fire off POE::Wheel::SocketFactory to begin the connection
  # process.

  my $request_index  = 0;
  my @free_sockets   = keys(%{$self->[SF_SOCKETS]});
  my $currently_open = keys(%{$self->[SF_USED]}) + @free_sockets;
  my @splice_list;

  QUEUED:
  foreach my $request (@{$self->[SF_QUEUE]}) {
    DEBUG and warn "checking for $request->[RQ_CONN_KEY]";

    # Sweep away requests that are marked as timed out.  That is,
    # requests without a valid timer ID.  Add the request index to the
    # splice list, and skip any further processing.

    unless (defined $request->[RQ_TIMER_ID]) {
      push @splice_list, $request_index;
      next;
    }

    # Skip this request if its scheme/address/port triple is maxed
    # out.

    my $req_key = $request->[RQ_CONN_KEY];
    next if (
      ($self->[SF_USED_EACH]{$req_key} || 0) >= $self->[SF_MAX_HOST]
    );

    # Honor the request from the free pool, if possible.  The
    # currently open socket count does not increase.

    my $existing_connection = $self->_check_free_pool($req_key);
    if ($existing_connection) {
      push @splice_list, $request_index;

      $kernel->alarm_remove($request->[RQ_TIMER_ID]);

      $kernel->post(
        $request->[RQ_SESSION],
        $request->[RQ_EVENT],
        {
          addr       => $request->[RQ_ADDRESS],
          context    => $request->[RQ_CONTEXT],
          port       => $request->[RQ_PORT],
          scheme     => $request->[RQ_SCHEME],
          connection => $existing_connection,
        }
      );
      next;
    }

    # Try to free over-committed (but unused) sockets until we're back
    # under SF_MAX_OPEN sockets.  Bail out if we can't free enough.
    # TODO - Consider removing @free_sockets in least- to
    # most-recently used order.
    while ($currently_open >= $self->[SF_MAX_OPEN]) {
      last QUEUED unless @free_sockets;
      my $next_to_go = splice(@free_sockets, rand(@free_sockets), 1);
      $self->_remove_socket_from_pool($next_to_go);
      $currently_open--;
    }

    # Start the request.  Create a wheel to begin the connection.
    # Move the wheel and its request into SF_WHEELS.
    DEBUG and warn "creating wheel for $req_key";
    my $wheel = POE::Wheel::SocketFactory->new(
      RemoteAddress => $request->[RQ_ADDRESS],
      RemotePort    => $request->[RQ_PORT],
      SuccessEvent  => "ka_conn_success",
      FailureEvent  => "ka_conn_failure",
    );

    $self->[SF_WHEELS]{$wheel->ID} = [
      $wheel,     # WHEEL_WHEEL
      $request,   # WHEEL_REQUEST
    ];

    $request->[RQ_WHEEL_ID] = $wheel->ID;

    # Count it as used, so we don't over commit file handles.
    $currently_open++;
    $self->[SF_USED_EACH]{$req_key}++;

    # Temporarily store the SF_USED record under the wheel ID.  It
    # will be moved to the socket when the wheel responds.
    $self->[SF_USED]{$wheel->ID} = [
      undef,     # USED_SOCKET
      time(),    # USED_TIME
      $req_key,  # USED_KEY
    ];

    # Mark the request index as one to splice out.

    push @splice_list, $request_index;
  }
  continue {
    $request_index++;
  }

  # The @splice_list is a list of element indices that need to be
  # spliced out of the request queue.  We scan in backwards, from
  # highest index to lowest, so that each splice does not affect the
  # indices of the other.
  #
  # This removes the request from the queue.  It's vastly important
  # that the request be entered into SF_WHEELS before now.

  my $splice_index = @splice_list;
  while ($splice_index--) {
    splice @{$self->[SF_QUEUE]}, $splice_list[$splice_index], 1;
  }
}

sub allocate {
  my $self = shift;
  croak "allocate() needs an even number of parameters" if @_ % 2;
  my %args = @_;

  # TODO - Validate arguments.

  my $scheme  = delete $args{scheme};
  croak "allocate() needs a 'scheme'"  unless $scheme;
  my $address = delete $args{addr};
  croak "allocate() needs an 'addr'"   unless $address;
  my $port    = delete $args{port};
  croak "allocate() needs a 'port'"    unless $port;
  my $event   = delete $args{event};
  croak "allocate() needs an 'event'"  unless $event;
  my $context = delete $args{context};
  croak "allocate() needs a 'context'" unless $context;
  my $timeout = delete $args{timeout};
  $timeout    = $self->[SF_TIMEOUT]    unless $timeout;

  my @unknown = sort keys %args;
  if (@unknown) {
    croak "allocate() doesn't accept: @unknown";
  }

  my $conn_key = "$scheme:$address:$port";

  # If we have a connection pool for the scheme/address/port triple,
  # then we can maybe return an available connection right away.

  my $existing_connection = $self->_check_free_pool($conn_key);
  return $existing_connection if $existing_connection;

  # We can't honor the request immediately, so it's put into a queue.
  DEBUG and warn "enqueuing request for $conn_key";

  my $request = [
    $poe_kernel->get_active_session(),  # RQ_SESSION
    $event,     # RQ_EVENT
    $scheme,    # RQ_SCHEME
    $address,   # RQ_ADDRESS
    $port,      # RQ_PORT
    $conn_key,  # RQ_CONN_KEY
    $context,   # RQ_CONTEXT
    $timeout,   # RQ_TIMEOUT
    time(),     # RQ_START
    undef,      # RQ_TIMER_ID
    undef,      # RQ_WHEEL_ID
  ];

  $poe_kernel->call("$self", "ka_set_timeout", $request);

  push @{ $self->[SF_QUEUE] }, $request;

  # If the queue has more than one request in it, then it already has
  # a wakeup event pending.  We don't need to send another one.

  return if @{$self->[SF_QUEUE]} > 1;

  # If the component's allocated socket count is maxed out, then it
  # will check the queue when an existing socket is released.  We
  # don't need to wake it up here.

  return if keys(%{$self->[SF_USED]}) >= $self->[SF_MAX_OPEN];

  # Likewise, we shouldn't awaken the session if there are no
  # available slots for the given scheme/address/port triple.  "|| 0"
  # to avoid an undef error.

  return if (
    ($self->[SF_USED_EACH]{$conn_key} || 0) >= $self->[SF_MAX_HOST]
  );

  # Wake the session up, and return nothing, signifying sound and fury
  # yet to come.
  DEBUG and warn "posting wakeup for $conn_key";
  $poe_kernel->post("$self", "ka_wake_up");
  return;
}

# Set the request's timeout, in the component's context.

sub _ka_set_timeout {
  my ($kernel, $request) = @_[KERNEL, ARG0];
  $request->[RQ_TIMER_ID] = $kernel->delay_set(
    ka_request_timeout => $request->[RQ_TIMEOUT], $request
  );
}

# The request has timed out.  Mark it as defunct, and respond with an
# ETIMEDOUT error.

sub _ka_request_timeout {
  my ($self, $kernel, $request) = @_[OBJECT, KERNEL, ARG0];

  $! = ETIMEDOUT;

  # The easiest way to do this?  Simulate an error from the wheel
  # itself.

  if (defined $request->[RQ_WHEEL_ID]) {
    @_[ARG0..ARG3] = ("connect", $!+0, "$@", $request->[RQ_WHEEL_ID]);
    goto &_ka_conn_failure;
  }

  # But what if there is no wheel?

  $kernel->post(
    $request->[RQ_SESSION],
    $request->[RQ_EVENT],
    {
      addr       => $request->[RQ_ADDRESS],
      context    => $request->[RQ_CONTEXT],
      port       => $request->[RQ_PORT],
      scheme     => $request->[RQ_SCHEME],
      connection => undef,
      function   => "connect",
      error_num  => $! + 0,
      error_str  => "$!",
    }
  );

  # And mark the request as dead.
  # TODO - Perhaps by using a separate flag, but the timer ID is
  # handy.

  $request->[RQ_TIMER_ID] = undef;
}

# Connection failed.  Remove the SF_WHEELS record corresponding to the
# request.  Remove the SF_USED placeholder record so it won't count
# anymore.  Send a failure notice to the requester.

sub _ka_conn_failure {
  my ($self, $func, $errnum, $errstr, $wheel_id) = @_[OBJECT, ARG0..ARG3];

  # Remove the SF_WHEELS record.
  my $wheel_rec = delete $self->[SF_WHEELS]{$wheel_id};
  my $request   = $wheel_rec->[WHEEL_REQUEST];

  # Remove the SF_USED placeholder.
  delete $self->[SF_USED]{$wheel_id};

  # Discount the use by request key, removing the SF_USED record
  # entirely if it's now moot.
  my $request_key = $request->[RQ_CONN_KEY];
  $self->_decrement_used_each($request_key);

  # Stop the timer.
  $_[KERNEL]->alarm_remove($request->[RQ_TIMER_ID]);
  $request->[RQ_TIMER_ID] = undef;

  # Tell the requester about the failure.
  $_[KERNEL]->post(
    $request->[RQ_SESSION],
    $request->[RQ_EVENT],
    {
      address    => $request->[RQ_ADDRESS],
      context    => $request->[RQ_CONTEXT],
      port       => $request->[RQ_PORT],
      scheme     => $request->[RQ_SCHEME],
      connection => undef,
      function   => $func,
      error_num  => $errnum,
      error_str  => $errstr,
    }
  );
}

# Connection succeeded.  Remove the SF_WHEELS record corresponding to
# the request.  Flesh out the placeholder SF_USED record so it counts.

sub _ka_conn_success {
  my ($self, $socket, $wheel_id) = @_[OBJECT, ARG0, ARG3];

  # Remove the SF_WHEELS record.
  my $wheel_rec = delete $self->[SF_WHEELS]{$wheel_id};
  my $request   = $wheel_rec->[WHEEL_REQUEST];

  # Remove the SF_USED placeholder, add in the socket, and store it
  # properly.
  my $used = delete $self->[SF_USED]{$wheel_id};

  $used->[USED_SOCKET] = $socket;

  $self->[SF_USED]{$socket} = $used;
  DEBUG and warn "posting... to $request->[RQ_SESSION] . $request->[RQ_EVENT]";

  # Stop the timer.
  $_[KERNEL]->alarm_remove($request->[RQ_TIMER_ID]);

  # Build a connection object around the socket.
  my $connection = POE::Component::Connection::Keepalive->new(
    socket  => $socket,
    manager => $self,
  );

  # Give the socket to the requester.
  $_[KERNEL]->post(
    $request->[RQ_SESSION],
    $request->[RQ_EVENT],
    {
      addr       => $request->[RQ_ADDRESS],
      context    => $request->[RQ_CONTEXT],
      port       => $request->[RQ_PORT],
      scheme     => $request->[RQ_SCHEME],
      connection => $connection,
    }
  );
}

# The user is done with a socket.  Make it available for reuse.

sub free {
  my ($self, $socket) = @_;

  # Remove the accompanying SF_USED record.
  croak "can't free() undefined socket" unless defined $socket;
  my $used = delete $self->[SF_USED]{$socket};
  croak "can't free() unallocated socket" unless defined $used;

  # Reclaim the socket.
  $poe_kernel->call("$self", "ka_reclaim_socket", $used);

  # Avoid returning things by mistake.
  return;
}

# A sink for deliberately unhandled events.

sub _ka_ignore_this_event {
  # Do nothing.
}

# An internal method to fetch a socket from the free pool, if one
# exists.

sub _check_free_pool {
  my ($self, $conn_key) = @_;

  return unless exists $self->[SF_POOL]{$conn_key};

  my $free = $self->[SF_POOL]{$conn_key};

  DEBUG and warn "reusing $conn_key";

  my $next_socket = (values %$free)[0];
  delete $free->{$next_socket};
  unless (keys %$free) {
    delete $self->[SF_POOL]{$conn_key};
  }

  # _check_free_pool() may be operating in another session, so we call
  # the correct one here.
  $poe_kernel->call("$self", "ka_relinquish_socket", $next_socket);

  $self->[SF_USED]{$next_socket} = [
    $next_socket,  # USED_SOCKET
    time(),        # USED_TIME
    $conn_key,     # USED_KEY
  ];

  delete $self->[SF_SOCKETS]{$next_socket};

  $self->[SF_USED_EACH]{$conn_key}++;

    # Build a connection object around the socket.
    my $connection = POE::Component::Connection::Keepalive->new(
      socket  => $next_socket,
      manager => $self,
    );

  return $connection;
}

sub _decrement_used_each {
  my ($self, $request_key) = @_;
  unless (--$self->[SF_USED_EACH]{$request_key}) {
    delete $self->[SF_USED_EACH]{$request_key};
  }
}

# Reclaim a socket.  Put it in the free socket pool, and wrap it with
# select_read() to discard any data and detect when it's closed.

sub _ka_reclaim_socket {
  my ($self, $kernel, $used) = @_[OBJECT, KERNEL, ARG0];

  my $socket = $used->[USED_SOCKET];

  # Decrement the usage counter for the given connection key.
  my $request_key = $used->[USED_KEY];
  $self->_decrement_used_each($request_key);

  # Watch the socket, and set a keep-alive timeout.
  $kernel->select_read($socket, "ka_socket_activity");
  my $timer_id = $kernel->delay_set(
    ka_keepalive_timeout => $self->[SF_KEEPALIVE], $socket
  );

  # Record the socket as free to be used.
  $self->[SF_POOL]{$request_key}{$socket} = $socket;
  $self->[SF_SOCKETS]{$socket} = [
    $request_key,       # SK_KEY
    $timer_id,          # SK_TIMER
  ];

  goto &_ka_wake_up;
}

# Socket timed out.  Discard it.

sub _ka_keepalive_timeout {
  my ($self, $socket) = @_[OBJECT, ARG0];
  $self->_remove_socket_from_pool($socket);
}

# Relinquish a socket.  Stop selecting on it.

sub _ka_relinquish_socket {
  my ($kernel, $socket) = @_[KERNEL, ARG0];
  $kernel->alarm_remove($_[OBJECT]->[SF_SOCKETS]{$socket}[SK_TIMER]);
  $kernel->select_read($socket, undef);
}

# Shut down the component.  Release any sockets we're currently
# holding onto.  Clean up any timers.  Remove the alias it's known by.

sub shutdown {
  my $self = shift;
  $poe_kernel->call("$self", "ka_shutdown");
}

sub _ka_shutdown {
  my ($self, $kernel) = @_[OBJECT, KERNEL];

  foreach my $sockets (values %{$self->[SF_POOL]}) {
    foreach my $socket (values %$sockets) {
      $kernel->alarm_remove($_[OBJECT]->[SF_SOCKETS]{$socket}[SK_TIMER]);
      $kernel->select_read($socket, undef);
    }
  }

  $kernel->alias_remove("$self");
}

# A socket in the free pool has activity.  Read from it and discard
# the output.  Discard the socket on error or remote closure.

sub _ka_socket_activity {
  my ($self, $kernel, $socket) = @_[OBJECT, KERNEL, ARG0];

  use bytes;
  return if sysread($socket, my $buf = "", 65536);

  $self->_remove_socket_from_pool($socket);
}

# Remove a socket from the free pool, by the socket handle itself.

sub _remove_socket_from_pool {
  my ($self, $socket) = @_;

  my $socket_rec = delete $self->[SF_SOCKETS]{$socket};
  my $key = $socket_rec->[SK_KEY];

  # Get the blessed version.
  $socket = delete $self->[SF_POOL]{$key}{$socket};

  unless (keys %{$self->[SF_POOL]{$key}}) {
    delete $self->[SF_POOL]{$key};
  }

  $poe_kernel->alarm_remove($socket_rec->[SK_TIMER]);
  $poe_kernel->select_read($socket, undef);
}

1;

__END__

=head1 NAME

POE::Component::Client::Keepalive - manage connections, with keep-alive

=head1 SYNOPSIS

  use warnings;
  use strict;

  use POE;
  use POE::Component::Client::Keepalive;

  POE::Session->create(
    inline_states => {
      _start    => \&start,
      got_conn  => \&got_conn,
      got_error => \&handle_error,
      got_input => \&handle_input,
      use_conn  => \&use_conn,
    }
  );

  POE::Kernel->run();
  exit;

  sub start {
    $_[HEAP]->{ka} = POE::Component::Client::Keepalive->new();

    my $conn = $_[HEAP]->{ka}->allocate(
      scheme  => "http",
      addr    => "127.0.0.1",
      port    => 9999,
      event   => "got_conn",
      context => "arbitrary data (even a reference) here",
      timeout => 60,
    );

    if (defined $conn) {
      print "Connection was returned from keep-alive cache.\n";
      $_[KERNEL]->yield(use_conn => $conn);
      return;
    }

    print "Connection is in progress.\n";
  }

  sub got_conn {
    my ($kernel, $heap, $response) = @_[KERNEL, HEAP, ARG0];

    my $conn    = $response->{connection};
    my $context = $response->{context};

    if (defined $conn) {
      print "Connection was established asynchronously.\n";
      $kernel->yield(use_conn => $conn);
      return;
    }

    print(
      "Connection could not be established: ",
      "$response->{function} error $response->{error_num}: ",
      "$response->{error_str}\n"
    );
  }

  sub use_conn {
    my ($heap, $conn) = @_[HEAP, ARG0];

    $heap->{connection} = $conn;
    $conn->start(
      InputEvent => "got_input",
      ErrorEvent => "got_error",
    );
  }

  sub handle_input {
    my $input = $_[ARG0];
    print "$input\n";
  }

  sub handle_error {
    my $heap = $_[HEAP];
    delete $heap->{connection};
    $heap->{ka}->shutdown();
  }

=head1 DESCRIPTION

POE::Component::Client::Keepalive creates and manages connections for
other components.  It maintains a cache of kept-alive connections for
quick reuse.  It is written specifically for clients that can benefit
from kept-alive connections, such as HTTP clients.  Using it for
one-shot connections would probably be silly.

=over 2

=item new

Creates a new keepalive connection manager.  A program may contain
several connection managers.  Each will operate independently of the
others.  None will know about the limits set in the others, so it's
possible to overrun your file descriptors for a process if you're not
careful.

new() takes up to four parameters.  All of them are optional.

To limit the number of simultaneous connections to a particular host
(defined by a combination of scheme, address and port):

  max_per_host => $max_simultaneous_host_connections, # defaults to 4

To limit the overall number of connections that may be open at once,
use

  max_open     => $maximum_open_connections, # defaults to 128

Programs are required to give connections back to the manager when
they are done.  See the free() method for how that works.  The
connection manager will keep connections alive for a period of time
before recycling them.  The maximum keep-alive time may be set with

  keep_alive   => $seconds_to_keep_free_conns_alive, # defaults to 15

Programs may not want to wait a long time for a connection to be
established.  They can set the request timeout to alter how long the
component holds a request before generating an error.

  timeout      => $seconds_to_process_a_request, # defaults to 120

=item allocate

Allocate a new connection.  Allocate() will return a connection
immediately if the keep-alive pool contains one matching the given
scheme, address, and port.  Otherwise allocate() will return undef and
begin establishing a connection asynchronously.  A message will be
posted back to the requesting session when the connection status is
finally known.

Allocate() requires five parameters and has an optional sixth.

Specify the scheme that will be used to communicate on the connection
(typically http or https).  The scheme is required.

  scheme  => $connection_scheme,

Request a connection to a particular address and port.  The address
and port must be numeric.  Both the address and port are required.

  address => $remote_address,
  port    => $remote_port,

Specify an name of the event to post when an asynchronous response is
ready.  The response event is required, but it won't be used if
allocate() can return a connection right away.

  event   => $return_event,

Set the connection timeout, in seconds.  The connection manager will
return an error (ETIMEDOUT) if it can't establish a connection within
the requested time.  This parameter is optional.  It will default to
the master timeout provided to the connection manager's constructor.

  timeout => $connect_timeout,

Specify additional contextual data.  The context defines the
connection's purpose.  It is used to maintain continuity between a
call to allocate() and an asynchronous response.  A context is
extremely handy, but it's optional.

  context => $context_data,

In summary:

  my $connection = $mgr->allocate(
    scheme   => "http",
    address  => "127.0.0.1",
    port     => 80,
    event    => "got_a_connection",
    context  => \%connection_context,
  );

The response event ("got_a_connection" in this example) contains
several fields, passed as a list of key/value pairs.  The list may be
assigned to a hash for convenience:

  sub got_a_connection {
    my %response = @_[ARG0..$#_];
    ...;
  }

Four of the fields exist to echo back your data:

  $response{address}    = $your_request_address;
  $response{context}    = $your_request_context;
  $response{port}       = $your_request_port;
  $response{scheme}     = $your_request_scheme;

One field returns the connection object if the connection was
successful, or undef if there was a failure:

  $response{connection} = $new_socket_handle;

Three other fields return error information if the connection failed.
They are not present if the connection was successful.

  $response{function}   = $name_of_failing_function;
  $response{error_num}  = $! as a number;
  $response{error_str}  = $! as a string;

=item free

Free() notifies the connection manager when connections are free to be
reused.  Freed connections are entered into the keep-alive pool and
may be returned by subsequent allocate() calls.

  $mgr->free($socket);

For now free() is called with a socket, not a connection object.  This
is usually not a problem since POE::Component::Connection::Keepalive
objects call free() for you when they are destroyed.

Not calling free() will cause a program to leak connections.  This is
also not generally a problem, since free() is called automatically
whenever connection objects are destroyed.

=item shutdown

The keep-alive pool requires connections to be active internally.
This may keep a program active even when all connections are idle.
The shutdown() method forces the connection manager to clear its
keep-alive pool, allowing a program to terminate gracefully.

  $mgr->shutdown();

=back

=head1 SEE ALSO

L<POE>
L<POE::Component::Connection::Keepalive>

=head1 BUGS

http://rt.cpan.org/NoAuth/Bugs.html?Dist=POE-Component-Client-Keepalive
tracks the known issues with this component.  You can add to them by
sending mail to bug-poe-component-client-keepalive@rt.cpan.org.

=head1 LICENSE

This distribution is copyright 2004 by Rocco Caputo.  All rights are
reserved.  This distribution is free software; you may redistribute it
and/or modify it under the same terms as Perl itself.

=head1 AUTHOR

Rocco Caputo <rcaputo@cpan.org>

Special thanks to Rob Bloodgood.

=cut
