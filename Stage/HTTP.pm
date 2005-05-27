# $Id: HTTP.pm,v 1.58 2004/10/02 15:37:11 rcaputo Exp $
# License and documentation are after __END__.

package POE::Component::Client::HTTP;

use strict;

sub DEBUG      () { 0 }
sub DEBUG_DATA () { 0 }

use vars qw($VERSION);
$VERSION = '0.65';

use Carp qw(croak);
use POSIX;
use Symbol qw(gensym);
use HTTP::Response;
use HTTP::Status qw(status_message);
use URI;
use HTML::HeadParser;

# Allow more finely grained timeouts if Time::HiRes is available.
BEGIN {
  local $SIG{'__DIE__'} = 'DEFAULT';
  eval {
    require Time::HiRes;
    Time::HiRes->import("time");
  };
}

use POE qw(
  Wheel::SocketFactory Wheel::ReadWrite
  Driver::SysRW Filter::Stream
);

BEGIN {
  my $has_client_dns = 0;
  eval {
    require POE::Component::Client::DNS;
    $has_client_dns = 1;
  };
  eval "sub HAS_CLIENT_DNS () { $has_client_dns }";
}

sub REQ_POSTBACK      () {  0 }
sub REQ_WHEEL         () {  1 }
sub REQ_REQUEST       () {  2 }
sub REQ_STATE         () {  3 }
sub REQ_RESPONSE      () {  4 }
sub REQ_BUFFER        () {  5 }
sub REQ_LAST_HEADER   () {  6 }
sub REQ_OCTETS_GOT    () {  7 }
sub REQ_NEWLINE       () {  8 }
sub REQ_TIMER         () {  9 }
sub REQ_PROG_POSTBACK () { 10 }
sub REQ_USING_PROXY   () { 11 }
sub REQ_HOST          () { 12 }
sub REQ_PORT          () { 13 }
sub REQ_START_TIME    () { 14 }
sub REQ_HEAD_PARSER   () { 15 }

sub RS_CONNECT      () { 0x01 }
sub RS_SENDING      () { 0x02 }
sub RS_IN_STATUS    () { 0x04 }
sub RS_IN_HEADERS   () { 0x08 }
sub RS_CHK_REDIRECT () { 0x10 }
sub RS_IN_CONTENT   () { 0x20 }
sub RS_DONE         () { 0x40 }

sub PROXY_HOST () { 0 }
sub PROXY_PORT () { 1 }

sub TRUE  () { 1 }
sub FALSE () { 0 }

sub DEFAULT_BLOCK_SIZE () { 4096 }

# Unique request ID, independent of wheel and timer IDs.

my $request_seq = 0;

# Bring in HTTPS support.

BEGIN {
  my $has_ssl = 0;
  eval { require POE::Component::Client::HTTP::SSL };
  if (
    defined $Net::SSLeay::VERSION and
    defined $Net::SSLeay::Handle::VERSION and
    $Net::SSLeay::VERSION >= 1.17 and
    $Net::SSLeay::Handle::VERSION >= 0.61
  ) {
    $has_ssl = 1;
  }
  eval "sub HAS_SSL () { $has_ssl }";
}

#------------------------------------------------------------------------------
# Spawn a new PoCo::Client::HTTP session.  This basically is a
# constructor, but it isn't named "new" because it doesn't create a
# usable object.  Instead, it spawns the object off as a separate
# session.

sub spawn {
  my $type = shift;

  croak "$type requires an even number of parameters" if @_ % 2;

  my %params = @_;

  my $alias = delete $params{Alias};
  $alias = 'weeble' unless defined $alias and length $alias;

  my $timeout = delete $params{Timeout};
  $timeout = 180 unless defined $timeout and $timeout >= 0;

  # Start a DNS resolver for this agent, if we can.
  if (HAS_CLIENT_DNS) {
    POE::Component::Client::DNS->spawn(
      Alias   => "poco_${alias}_resolver",
      Timeout => $timeout,
    );
  }

  # Accept an agent, or a reference to a list of agents.
  my $agent = delete $params{Agent};
  $agent = [] unless defined $agent;
  if (ref($agent) eq "") {
    $agent = [ $agent ];
  }
  unless (ref($agent) eq "ARRAY") {
    croak "Agent must be a scalar or a reference to a list of agent strings";
  }

  push(
    @$agent,
    sprintf(
      'POE-Component-Client-HTTP/%s (perl; N; POE; en; rv:%f)',
      $VERSION, $VERSION
    )
  ) unless @$agent;

  my $max_size = delete $params{MaxSize};

  my $streaming = delete $params{Streaming};

  my $protocol = delete $params{Protocol};
  $protocol = 'HTTP/1.0' unless defined $protocol and length $protocol;

  my $cookie_jar = delete $params{CookieJar};
  my $from       = delete $params{From};
  my $no_proxy   = delete $params{NoProxy};
  my $proxy      = delete $params{Proxy};
  my $frmax      = delete $params{FollowRedirects};

  # Process HTTP_PROXY and NO_PROXY environment variables.

  $proxy    = $ENV{HTTP_PROXY} || $ENV{http_proxy} unless defined $proxy;
  $no_proxy = $ENV{NO_PROXY}   || $ENV{no_proxy}   unless defined $no_proxy;

  # Translate environment variable formats into internal versions.

  if (defined $proxy) {
    if (ref($proxy) eq 'ARRAY') {
      croak "Proxy must contain [HOST,PORT]" unless @$proxy == 2;
      $proxy = [ $proxy ];
    }
    else {
      my @proxies = split /\s*\,\s*/, $proxy;
      foreach (@proxies) {
        s/^http:\/+//;
        s/\/+$//;
        croak "Proxy must contain host:port" unless /^(.+):(\d+)$/;
        $_ = [ $1, $2 ];
      }
      $proxy = \@proxies;
    }
  }

  if (defined $no_proxy) {
    unless (ref($no_proxy) eq 'ARRAY') {
      $no_proxy = [ split(/\s*\,\s*/, $no_proxy) ];
    }
  }

  croak(
    "$type doesn't know these parameters: ",
    join(', ', sort keys %params)
  ) if scalar keys %params;

  POE::Session->create(
    inline_states => {
      _start  => \&poco_weeble_start,
      _stop   => \&poco_weeble_stop,

      # Public interface.
      request => \&poco_weeble_request,
      pending_requests_count => \&poco_weeble_pending_requests_count,

      # Net::DNS interface.
      got_dns_response  => \&poco_weeble_dns_answer,
      do_connect        => \&poco_weeble_do_connect,

      # SocketFactory interface.
      got_connect_done  => \&poco_weeble_connect_ok,
      got_connect_error => \&poco_weeble_connect_error,

      # ReadWrite interface.
      got_socket_input  => \&poco_weeble_io_read,
      got_socket_flush  => \&poco_weeble_io_flushed,
      got_socket_error  => \&poco_weeble_io_error,

      # I/O timeout.
      got_timeout       => \&poco_weeble_timeout,
    },
    heap => {
      alias       => $alias,
      timeout     => $timeout,
      cookie_jar  => $cookie_jar,
      proxy       => $proxy,
      no_proxy    => $no_proxy,
      frmax       => $frmax,
      agent       => $agent,
      from        => $from,
      protocol    => $protocol,
      max_size    => $max_size,
      streaming   => $streaming,
    },
  );

  undef;
}

#------------------------------------------------------------------------------

sub poco_weeble_start {
  my ($kernel, $heap) = @_[KERNEL, HEAP];

  DEBUG and do {
    sub no_undef { (defined $_[0]) ? $_[0] : "(undef)" };
    sub no_undef_list { (defined $_[0]) ? "@{$_[0]}" : "(undef)" };
    warn(
      ",--- starting a http client component ----\n",
      "| alias     : $heap->{alias}\n",
      "| timeout   : $heap->{timeout}\n",
      "| agent     : ", no_undef_list($heap->{agent}), "\n",
      "| protocol  : $heap->{protocol}\n",
      "| max_size  : ", no_undef($heap->{max_size}), "\n",
      "| streaming : ", no_undef($heap->{streaming}), "\n",
      "| cookie_jar: ", no_undef($heap->{cookie_jar}), "\n",
      "| from      : ", no_undef($heap->{from}), "\n",
      "| proxy     : ", no_undef_list($heap->{proxy}), "\n",
      "| no_proxy  : ", no_undef_list($heap->{no_proxy}), "\n",
      "`-----------------------------------------\n",
    );
  };

  $kernel->alias_set($heap->{alias});
}

#------------------------------------------------------------------------------

sub poco_weeble_stop {
  my $heap = shift;
  delete $heap->{request};
  DEBUG and warn "$heap->{alias} stopped.\n";
}

sub poco_weeble_pending_requests_count {
  my ($heap) = $_[HEAP];
  my $r = $heap->{request} || {};
  return keys %$r;
}

#------------------------------------------------------------------------------

sub poco_weeble_request {
  my (
    $kernel, $heap, $sender,
    $response_event, $http_request, $tag, $progress_event
  ) = @_[KERNEL, HEAP, SENDER, ARG0, ARG1, ARG2, ARG3];

  # Add a protocol if one isn't included.
  $http_request->protocol( $heap->{protocol} )
    unless (
      defined $http_request->protocol()
      and length $http_request->protocol()
    );


  # MEXNIX 2002-06-01: If we have a proxy set, and the request URI is
  # not in our no_proxy, then use the proxy.  Otherwise use the
  # request URI.

  # Get the host and port from the request object.
  my ($host, $port, $scheme, $using_proxy);

  eval {
    $host   = $http_request->uri()->host();
    $port   = $http_request->uri()->port();
    $scheme = $http_request->uri()->scheme();
  };
  warn($@), return if $@;

  # Add a host header if one isn't included.  Must do this before 
  # we reset the $host for the proxy!
  unless (
    defined $http_request->header('Host')
    and length $http_request->header('Host')
  ) {
    # Add port only if non-standard.
    if ($port == 80) {
      $http_request->header( Host => $host );
    }
    else {
      $http_request->header( Host => "$host:$port" )
    }
  }

  if (defined $heap->{proxy} and not _in_no_proxy($host, $heap->{no_proxy})) {
    my $proxy = $heap->{proxy}->[rand @{$heap->{proxy}}];
    $host = $proxy->[PROXY_HOST];
    $port = $proxy->[PROXY_PORT];
    $using_proxy = TRUE;
  }
  else {
    $using_proxy = FALSE;
  }

  # Add an agent header if one isn't included.
  unless (defined $http_request->user_agent()) {
    if (@{$heap->{agent}}) {
      my $this_agent = $heap->{agent}->[rand @{$heap->{agent}}];
      $http_request->user_agent($this_agent);
    }
  }

  # Add a from header if one isn't included.
  if (defined $heap->{from} and length $heap->{from}) {
    $http_request->from( $heap->{from} )
      unless (
        defined $http_request->from
        and length $http_request->from
      );
  }

  # Create a progress postback if requested.
  my $progress_postback;
  $progress_postback = $sender->postback($progress_event, $http_request, $tag)
    if defined $progress_event;

  # If we have a cookie jar, have it frob our headers.  LWP rocks!
  if (defined $heap->{cookie_jar}) {
    $heap->{cookie_jar}->add_cookie_header($http_request);
  }

  DEBUG and warn "weeble got a request...\n";

  # Get a unique request ID.
  my $request_id = ++$request_seq;

  # Build the request.
  my $request = [
    $sender->postback( $response_event, $http_request, $tag ), # REQ_POSTBACK
    undef,              # REQ_WHEEL
    $http_request,      # REQ_REQUEST
    RS_CONNECT,         # REQ_STATE
    undef,              # REQ_RESPONSE
    '',                 # REQ_BUFFER
    undef,              # REQ_LAST_HEADER
    0,                  # REQ_OCTETS_GOT
    "\x0D\x0A",         # REQ_NEWLINE
    undef,              # REQ_TIMER
    $progress_postback, # REQ_PROG_POSTBACK
    $using_proxy,       # REQ_USING_PROXY
    $host,              # REQ_HOST
    $port,              # REQ_PORT
    time(),             # REQ_START_TIME
    undef,              # REQ_HEAD_PARSER
  ];

  if($heap->{frmax}) {
    my $uri = $http_request->uri()->as_string();
    if (defined $tag && $tag =~ s/_redir_//) {
      $request->[REQ_POSTBACK] = $heap->{request}->{$tag}->[REQ_POSTBACK];
      $heap->{redir}->{$request_id}->{from} = $tag;
      @{$heap->{redir}->{$request_id}->{hist}} =
        @{$heap->{redir}->{$tag}->{hist}};
    }
    push @{$heap->{redir}->{$request_id}->{hist}}, $uri;
  }

  # Bail out if no SSL and we need it.
  if ($http_request->uri->scheme() eq 'https') {
    unless (HAS_SSL) {
      _post_error($request, "Net::SSLeay 1.17 or newer is required for https");
      return;
    }
  }

  # If non-blocking DNS is available, and the host was supplied as a
  # name, then go through POE::Component::Client::DNS.  Otherwise go
  # directly to the SocketFactory stage.  -><- Should probably check
  # for IPv6 addresses here, too.

  if (HAS_CLIENT_DNS and $host !~ /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/) {

    if (exists $heap->{resolve}->{$host}) {
      DEBUG and warn "DNS: $host is piggybacking on a pending lookup.\n";
      push @{$heap->{resolve}->{$host}}, $request_id;
    }
    else {
      DEBUG and warn "DNS: $host is being looked up in the background.\n";
      $heap->{resolve}->{$host} = [ $request_id ];
      my $my_alias = $heap->{alias};
      $kernel->post(
        "poco_${my_alias}_resolver" =>
        resolve => got_dns_response => $host => "A", "IN"
      );
    }
  }
  else {
    DEBUG and warn "DNS: $host may block while it's looked up.\n";
    $kernel->yield( do_connect => $request_id, $host );
  }

  $heap->{request}->{$request_id} = $request;
}

#------------------------------------------------------------------------------
# Non-blocking DNS lookup stage.

sub poco_weeble_dns_answer {
  my ($kernel, $heap) = @_[KERNEL, HEAP];
  my $request_address = $_[ARG0]->[0];
  my $response_object = $_[ARG1]->[0];
  my $response_error  = $_[ARG1]->[1];

  my $requests = delete $heap->{resolve}->{$request_address};

  DEBUG and warn $request_address;

  # No requests are on record for this lookup.
  die unless defined $requests;

  # No response.
  unless (defined $response_object) {
    foreach my $request_id (@$requests) {
      my $request = delete $heap->{request}->{$request_id};
      _post_error($request, $response_error);
    }
    return;
  }

  # A response!
  foreach my $answer ($response_object->answer()) {
    next unless $answer->type eq "A";

    DEBUG and
      warn "DNS: $request_address resolves to ", $answer->rdatastr(), "\n";

    foreach my $request_id (@$requests) {
      $kernel->yield( do_connect => $request_id, $answer->rdatastr );
    }

    # Return after the first good answer.
    return;
  }

  # Didn't return here.  No address record for the host?
  foreach my $request_id (@$requests) {
    my $request = delete $heap->{request}->{$request_id};
    _post_error($request, "Host has no address.");
  }
}

#------------------------------------------------------------------------------

sub poco_weeble_do_connect {
  my ($kernel, $heap, $request_id, $address) = @_[KERNEL, HEAP, ARG0, ARG1];

  my $request = $heap->{request}->{$request_id};

  # Create a socket factory.
  my $socket_factory =
    $request->[REQ_WHEEL] =
      POE::Wheel::SocketFactory->new(
        RemoteAddress => $address,
        RemotePort    => $request->[REQ_PORT],
        SuccessEvent  => 'got_connect_done',
        FailureEvent  => 'got_connect_error',
      );

  # Create a timeout timer.
  $request->[REQ_TIMER] =
    $kernel->delay_set(
      got_timeout =>
      $heap->{timeout} - (time() - $request->[REQ_START_TIME]) =>
      $request_id
    );

  # Cross-reference the wheel and timer IDs back to the request.
  $heap->{timer_to_request}->{$request->[REQ_TIMER]} = $request_id;
  $heap->{wheel_to_request}->{$socket_factory->ID()} = $request_id;

  DEBUG and
    warn(
      "wheel ", $socket_factory->ID,
      " is connecting to $request->[REQ_HOST] : $request->[REQ_PORT] ...\n"
    );
}

#------------------------------------------------------------------------------

sub poco_weeble_connect_ok {
  my ($heap, $socket, $wheel_id) = @_[HEAP, ARG0, ARG3];

  DEBUG and warn "wheel $wheel_id connected ok...\n";

  # Remove the old wheel ID from the look-up table.
  my $request_id = delete $heap->{wheel_to_request}->{$wheel_id};
  die unless defined $request_id;

  my $request = $heap->{request}->{$request_id};

  # Switch the handle to SSL if we're doing that.
  if ($request->[REQ_REQUEST]->uri->scheme() eq 'https') {
    DEBUG and warn "wheel $wheel_id switching to SSL...\n";

    # Net::SSLeay needs blocking for setup.
    #
    # ActiveState Perl 5.8.0 dislikes the Win32-specific code to make
    # a socket blocking, so we use IO::Handle's blocking(1) method.
    # Perl 5.005_03 doesn't like blocking(), so we only use it in
    # 5.8.0 and beyond.
    #
    # TODO - This code should probably become a POE::Kernel method,
    # seeing as it's rather baroque and potentially useful in a number
    # of places.
    my $old_socket = $socket;
    if ($] >= 5.008) {
      $old_socket->blocking(1);
    }
    else {
      # Make the handle blocking, the POSIX way.
      unless ($^O eq 'MSWin32') {
        my $flags = fcntl($old_socket, F_GETFL, 0)
          or die "fcntl($old_socket, F_GETFL, etc.) fails: $!";
        until (fcntl($old_socket, F_SETFL, $flags & ~O_NONBLOCK)) {
          die "fcntl($old_socket, FSETFL, etc) fails: $!"
            unless $! == EAGAIN or $! == EWOULDBLOCK;
        }
      }
      # Do it the Win32 way.
      else {
        my $set_it = "0";

        # 126 is FIONBIO (some docs say 0x7F << 16)
        ioctl( $old_socket,
               0x80000000 | (4 << 16) | (ord('f') << 8) | 126,
               $set_it
             )
          or die "ioctl($old_socket, FIONBIO, $set_it) fails: $!";
      }
    }

    $socket = gensym();
    tie(
      *$socket,
      "POE::Component::Client::HTTP::SSL",
      $old_socket
    ) or die $!;

    DEBUG and warn "wheel $wheel_id switched to SSL...\n";
  }

  my $block_size = $heap->{streaming} || DEFAULT_BLOCK_SIZE;
  $block_size = DEFAULT_BLOCK_SIZE if $block_size < 1;

  # Make a ReadWrite wheel to interact on the socket.
  my $new_wheel = POE::Wheel::ReadWrite->new(
    Handle       => $socket,
    Driver       => POE::Driver::SysRW->new(BlockSize => $block_size),
    Filter       => POE::Filter::Stream->new(),
    InputEvent   => 'got_socket_input',
    FlushedEvent => 'got_socket_flush',
    ErrorEvent   => 'got_socket_error',
  );

  DEBUG and warn "wheel $wheel_id became wheel ", $new_wheel->ID, "\n";

  # Add the new wheel ID to the lookup table.

  $heap->{wheel_to_request}->{ $new_wheel->ID() } = $request_id;

  # Switch wheels.  This is a bit cumbersome, but it works around a
  # bug in older versions of POE.

  $request->[REQ_WHEEL] = undef;
  $request->[REQ_WHEEL] = $new_wheel;

  # We're now in a sending state.
  $request->[REQ_STATE] = RS_SENDING;

  # Put the request.  HTTP::Request's as_string() method isn't quite
  # right.  It uses the full URL on the request line, so we have to
  # put the request in pieces.

  my $http_request = $request->[REQ_REQUEST];

  # MEXNIX 2002-06-01: Check for proxy.  Request query is a bit
  # different...

  my $request_uri;
  if ($request->[REQ_USING_PROXY]) {
    $request_uri = $http_request->uri()->canonical();
  }
  else {
    $request_uri = $http_request->uri()->canonical()->path_query();
  }

  my $request_string = (
    $http_request->method() . ' ' .
    $request_uri . ' ' .
    $http_request->protocol() . "\x0D\x0A" .
    $http_request->headers_as_string("\x0D\x0A") . "\x0D\x0A" .
    $http_request->content() # . "\x0D\x0A"
  );

  DEBUG and do {
    my $formatted_request_string = $request_string;
    $formatted_request_string =~ s/([^\n])$/$1\n/;
    $formatted_request_string =~ s/^/| /mg;
    warn ",----- SENDING REQUEST ", '-' x 56, "\n";
    warn $formatted_request_string;
    warn "`", '-' x 78, "\n";
  };

  $request->[REQ_WHEEL]->put( $request_string );
}

#------------------------------------------------------------------------------

sub poco_weeble_connect_error {
  my ($kernel, $heap, $operation, $errnum, $errstr, $wheel_id) =
    @_[KERNEL, HEAP, ARG0..ARG3];

  DEBUG and
    warn "wheel $wheel_id encountered $operation error $errnum: $errstr\n";

  # Drop the wheel.  If there's no request for this wheel, it may have
  # timed out earlier.  Just return in that case.
  my $request_id = delete $heap->{wheel_to_request}->{$wheel_id};
  die "expected a request ID, but there is none" unless defined $request_id;

  # TODO - Jeff Bisbee is testing this alternate behavior.
  # return unless defined $request_id;

  # Drop its cross-references.
  my $request = delete $heap->{request}->{$request_id};

  # Stop the timeout timer for this wheel, too.
  my $alarm_id = $request->[REQ_TIMER];
  if (delete $heap->{timer_to_request}->{ $alarm_id }) {
    $kernel->alarm_remove( $alarm_id );
  }

  # Post an error response back to the requesting session.
  _post_error($request, "$operation error $errnum: $errstr");
}

#------------------------------------------------------------------------------

sub poco_weeble_timeout {
  my ($kernel, $heap, $request_id) = @_[KERNEL, HEAP, ARG0];

  DEBUG and warn "request $request_id timed out\n";

  # Discard the request.  Keep a copy for a few bits of cleanup.
  my $request = delete $heap->{request}->{$request_id};

  # There's a wheel attached to the request.  Shut it down.
  if (defined $request->[REQ_WHEEL]) {
    my $wheel_id = $request->[REQ_WHEEL]->ID();
    DEBUG and warn "request $request_id is wheel $wheel_id\n";
    delete $heap->{wheel_to_request}->{$wheel_id};
  }

  # No need to remove the alarm here because it's already gone.
  delete $heap->{timer_to_request}->{ $request->[REQ_TIMER] };

  # Post an error response back to the requesting session.
  $request->[REQ_POSTBACK]->(HTTP::Response->new(408, "Request timed out"));
}

#------------------------------------------------------------------------------

sub poco_weeble_io_flushed {
  my ($heap, $wheel_id) = @_[HEAP, ARG0];

  DEBUG and warn "wheel $wheel_id flushed its request...\n";

  # We sent the request.  Now we're looking for a response.  It may be
  # bad to assume we won't get a response until a request has flushed.
  my $request_id = $heap->{wheel_to_request}->{$wheel_id};
  die "request id needed" unless defined $request_id;

  my $request = $heap->{request}->{$request_id};
  $request->[REQ_STATE] = RS_IN_STATUS;
  # XXX - Removed a second time.  The first time was in version 0.53,
  # because the EOF generated by shutdown_output() causes some servers
  # to disconnect rather than send their responses.
  # $request->[REQ_WHEEL]->shutdown_output();
}

#------------------------------------------------------------------------------

sub poco_weeble_io_error {
  my ($kernel, $heap, $operation, $errnum, $errstr, $wheel_id) =
    @_[KERNEL, HEAP, ARG0..ARG3];

  DEBUG and
    warn "wheel $wheel_id encountered $operation error $errnum: $errstr\n";

  # Drop the wheel.  If there's no request for this wheel, it may have
  # timed out earlier.  Just return in that case.
  my $request_id = delete $heap->{wheel_to_request}->{$wheel_id};
  die "expected a request ID, but there is none" unless defined $request_id;

  # TODO - Jeff Bisbee is testing this alternate behavior.
  # return unless defined $request_id;

  # Drop its cross-references.
  my $request = delete $heap->{request}->{$request_id};

  # Stop the timeout timer for this wheel, too.
  my $alarm_id = $request->[REQ_TIMER];
  if (delete $heap->{timer_to_request}->{ $alarm_id }) {
    $kernel->alarm_remove( $alarm_id );
  }

  # If there was a non-zero error, then something bad happened.  Post
  # an error response back.
  if ($errnum) {
    $request->[REQ_POSTBACK]->(
      HTTP::Response->new( 400, "$operation error $errnum: $errstr" )
    );
    return;
  }

  # Otherwise the remote end simply closed.  If we've built a
  # response, then post it back.
  if ($request->[REQ_STATE] & (RS_IN_CONTENT | RS_DONE)) {

    # If we have a cookie jar, have it frob our headers.  LWP rocks!
    if (defined $heap->{cookie_jar}) {
      $heap->{cookie_jar}->extract_cookies($request->[REQ_RESPONSE]);
    }

    # If we're streaming, the response is HTTP::Response without
    # content and undef to signal the end of the stream.  Otherwise
    # it's the entire HTTP::Response object we've carefully built.
    if ($heap->{streaming}) {
      $request->[REQ_POSTBACK]->(
        $request->[REQ_RESPONSE], undef
      );
    }
    else {
      _respond($heap, $request_id, $request);
    }
    return;
  }

  # We haven't built a proper response.  Send back an error.
  $request->[REQ_POSTBACK]->(
    HTTP::Response->new( 400, "incomplete response" )
  );
}

#------------------------------------------------------------------------------
# Read a chunk of response.  This code is directly adapted from Artur
# Bergman's nifty POE::Filter::HTTPD, which does pretty much the same
# in the other direction.

sub poco_weeble_io_read {
  my ($kernel, $heap, $input, $wheel_id) = @_[KERNEL, HEAP, ARG0, ARG1];
  my $request_id = $heap->{wheel_to_request}->{$wheel_id};
  die unless defined $request_id;
  my $request = $heap->{request}->{$request_id};

  DEBUG and warn "wheel $wheel_id got input...\n";
  DEBUG_DATA and warn(_hexdump($input), "\n");

  # Reset the timeout if we get data.
  $kernel->delay_adjust($request->[REQ_TIMER], $heap->{timeout});

  # Aggregate the new input.
  $request->[REQ_BUFFER] .= $input;

  # The very first line ought to be status.  If it's not, then it's
  # part of the content.
  if ($request->[REQ_STATE] & RS_IN_STATUS) {
    # Parse a status line. Detects the newline type, because it has to
    # or bad servers will break it.  What happens if someone puts
    # bogus headers in the content?
    if (
      $request->[REQ_BUFFER] =~
        s/^(HTTP\/[\d\.]+)? *(\d+) *(.*?)([\x0D\x0A]+)([^\x0D\x0A])/$5/
    ) {
      DEBUG and
        warn "wheel $wheel_id got a status line... moving to headers.\n";

      my $protocol;
      if (defined $1) {
        $protocol = $1;
      }
      else {
        $protocol= 'HTTP/0.9';
      }

      DEBUG_DATA and
        warn "wheel $wheel_id status: proto($protocol) code($2) msg($3)\n";

      $request->[REQ_STATE]    = RS_IN_HEADERS;
      $request->[REQ_NEWLINE]  = $4;
      $request->[REQ_RESPONSE] = HTTP::Response->new(
        $2,
        $3 || status_message($2),
      );
      $request->[REQ_RESPONSE]->protocol( $protocol );
      $request->[REQ_RESPONSE]->request( $request->[REQ_REQUEST] );
    }

    # No status line.  We go straight into content.  Since we don't
    # know the status, we don't purport to.
    elsif ($request->[REQ_BUFFER] =~ /[\x0D\x0A]+[^\x0D\x0A]/) {
      DEBUG and warn "wheel $wheel_id got no status... moving to content.\n";
      $request->[REQ_RESPONSE] = HTTP::Response->new();
      $request->[REQ_STATE] = RS_IN_CONTENT;
    }

    # We need more data to match the status line.
    else {
      return;
    }
  }

  # Parse the input for headers.  This isn't in an else clause because
  # we may go from status to content in the same read.
  if ($request->[REQ_STATE] & RS_IN_HEADERS) {
    # Parse it by lines. -><- Assumes newlines are consistent with the
    # status line.  I just know this is too much to ask.
HEADER:
    while (
      $request->[REQ_BUFFER] =~
      s/^(.*?)($request->[REQ_NEWLINE]|\x0D?\x0A)//
    ) {
      # This line means something.
      if (length $1) {
        my $line = $1;

        # New header.
        if ($line =~ /^([\w\-]+)\s*\:\s*(.+?)\s*$/) {
          DEBUG and warn "wheel $wheel_id got a new header: $1 ...\n";

          $request->[REQ_LAST_HEADER] = $1;
          $request->[REQ_RESPONSE]->push_header($1, $2);
        }

        # Continued header.
        elsif ($line =~ /^\s+(.+?)\s*$/) {
          if (defined $request->[REQ_LAST_HEADER]) {
            DEBUG and
              warn(
                "wheel $wheel_id got a continuation for header ",
                $request->[REQ_LAST_HEADER],
                " ...\n"
              );

            $request->[REQ_RESPONSE]->push_header(
              $request->[REQ_LAST_HEADER], $1
            );
          }
          else {
            DEBUG and warn "wheel $wheel_id got continued status message...\n";

            my $message = $request->[REQ_RESPONSE]->message();
            $message .= " " . $1;
            $request->[REQ_RESPONSE]->message($message);
          }
        }

        # Dunno what.
        else {
          # -><- bad request?
          DEBUG and warn "wheel $wheel_id got strange header line: <$line>";
        }
      }

      # This line is empty; we eat it and switch to RS_CHK_REDIRECT.
      else {
        DEBUG and
          warn(
            "wheel $wheel_id got a blank line... ".
            "headers done, check for redirection.\n"
          );
        $request->[REQ_STATE] = RS_CHK_REDIRECT;
        last HEADER;
      }
    }
  }

  # Edge case between RS_IN_HEADERS and RS_IN_CONTENT.  We'll see if
  # HTML header parsing is necessary (and enable it if it is).  We'll
  # also check for redirection, if enabled.
  if ($request->[REQ_STATE] & RS_CHK_REDIRECT) {
    # We only go through this once per request.
    $request->[REQ_STATE] = RS_IN_CONTENT;

    # Check for redirection, if enabled. Yield request to ourselves.
    # Prevent looping, either through maximum hops, or repeat.
    #
    # -><- I wonder.  Will we need to defer the redirect check until
    # the HTML <HEAD></HEAD> section is loaded?  Headers in there may
    # alter the response's base() result.  Would that be significant?
    if ($request->[REQ_RESPONSE]->is_redirect() && $heap->{frmax}) {
      my $uri = $request->[REQ_RESPONSE]->header('Location');
      # Canonicalize relative URIs.
      my $base = $request->[REQ_RESPONSE]->base();
      $uri = URI->new($uri, $base)->abs($base);

      DEBUG and warn "Redirected to ".$uri."\n";

      my @history = @{$heap->{redir}->{$request_id}->{hist}};
      if(@history > 5 || grep($uri eq $_, @history)) {
        $request->[REQ_STATE] = RS_DONE;
        DEBUG and warn "Too much redirection, moving to done\n";
      }
      else { # All fine, yield new request and mark this disabled.
        my $newrequest = $request->[REQ_REQUEST]->clone();
	$newrequest->uri($uri);

        my ($new_host, $new_port);
        eval {
          $new_host = $uri->host();
          $new_port = $uri->port();
          if ($new_port == 80) {
            $newrequest->header( Host => $new_host );
          }
          else {
            $newrequest->header( Host => "$new_host:$new_port" );
          }
        };
        warn $@ if $@;

        $kernel->yield(
          request => 'dummystate',
          $newrequest, "_redir_".$request_id,
          $request->[REQ_PROG_POSTBACK]
        );
	$heap->{redir}->{$request_id}->{request} = $request->[REQ_REQUEST];
        $heap->{redir}->{$request_id}->{followed} = 1; # Mark redirected.
      }
    }

    # Not a redirect.  Begin parsing headers if this is HTML.
    else {
      if ($request->[REQ_RESPONSE]->content_type() eq "text/html") {
        $request->[REQ_HEAD_PARSER] = HTML::HeadParser->new(
          $request->[REQ_RESPONSE]->{_headers}
        );
      }
    }
  }

  # We're in a content state.  This isn't an else clause because we
  # may go from header to content in the same read.
  if ($request->[REQ_STATE] & RS_IN_CONTENT) {

    # First pass the new chunk through our HeadParser, if we have one.
    # This also destroys the HeadParser if its purpose is done.
    if ($request->[REQ_HEAD_PARSER]) {
      $request->[REQ_HEAD_PARSER]->parse($request->[REQ_BUFFER]) or
        $request->[REQ_HEAD_PARSER] = undef;
    }

    # Count how many octets we've received.  -><- This may fail on
    # perl 5.8 if the input has been identified as Unicode.  Then
    # again, the C<use bytes> in Driver::SysRW may have untainted the
    # data... or it may have just changed the semantics of length()
    # therein.  If it's done the former, then we're safe.  Otherwise
    # we also need to C<use bytes>.
    my $this_chunk_length = length($request->[REQ_BUFFER]);
    $request->[REQ_OCTETS_GOT] += $this_chunk_length;

    # We've gone over the maximum content size to return.  Chop it
    # back.
    if ($heap->{max_size} and $request->[REQ_OCTETS_GOT] > $heap->{max_size}) {
      my $over = $request->[REQ_OCTETS_GOT] - $heap->{max_size};
      $request->[REQ_OCTETS_GOT] -= $over;
      substr($request->[REQ_BUFFER], -$over) = "";
    }

    # If we are streaming, send the chunk back to the client session.
    # Otherwise add the new octets to the response's content.  -><-
    # This should only add up to content-length octets total!
    if ($heap->{streaming}) {
      $request->[REQ_POSTBACK]->(
        $request->[REQ_RESPONSE], $request->[REQ_BUFFER]
      );
    }
    else {
      $request->[REQ_RESPONSE]->add_content($request->[REQ_BUFFER]);
    }

    DEBUG and do {
      warn "wheel $wheel_id got $this_chunk_length octets of content...\n";
      warn(
        "wheel $wheel_id has $request->[REQ_OCTETS_GOT]",
        (
          $request->[REQ_RESPONSE]->content_length()
          ? ( " out of " . $request->[REQ_RESPONSE]->content_length() )
          : ""
        ),
        " octets\n"
      );
    };

    # Stop reading when we have enough content.  -><- Should never be
    # greater than our content length.
    if ( $request->[REQ_RESPONSE]->content_length() ) {

      # TODO - Remove this?  Or pass the information to the user?
      #my $progress = int( ($request->[REQ_OCTETS_GOT] * 100) /
      #                    $request->[REQ_RESPONSE]->content_length()
      #                  );

      $request->[REQ_PROG_POSTBACK]->(
        $request->[REQ_OCTETS_GOT],
        $request->[REQ_RESPONSE]->content_length(),
        $request->[REQ_BUFFER],
      ) if $request->[REQ_PROG_POSTBACK];

      if (
        $request->[REQ_OCTETS_GOT] >= $request->[REQ_RESPONSE]->content_length()
      ) {
        DEBUG and
          warn "wheel $wheel_id has a full response... moving to done.\n";

        $request->[REQ_STATE] = RS_DONE;

        # -><- This assumes the server will now disconnect.  That will
        # give us an error 0 (socket's closed), and we will post the
        # response.
      }
    }
  }

  $request->[REQ_BUFFER] = '' unless $request->[REQ_STATE] & RS_IN_HEADERS;

  unless ($request->[REQ_STATE] & RS_DONE) {
    if (
      defined($heap->{max_size}) and
      $request->[REQ_OCTETS_GOT] >= $heap->{max_size}
    ) {
      DEBUG and
        warn "wheel $wheel_id got enough data... moving to done.\n";

      if (
        defined($request->[REQ_RESPONSE]) and
        defined($request->[REQ_RESPONSE]->code())
      ) {
        $request->[REQ_RESPONSE]->header(
          'X-Content-Range',
          'bytes 0-' . $request->[REQ_OCTETS_GOT] .
          (
            $request->[REQ_RESPONSE]->content_length()
            ? ('/' . $request->[REQ_RESPONSE]->content_length())
            : ''
          )
        );
      }
      else {
        $request->[REQ_RESPONSE] =
          HTTP::Response->new( 400, "Response too large (and no headers)" );
      }

      $request->[REQ_STATE] = RS_DONE;

      # Hang up on purpose.
      my $request_id = delete $heap->{wheel_to_request}->{$wheel_id};
      my $request = delete $heap->{request}->{$request_id};

      # Stop the timeout timer for this wheel, too.
      my $alarm_id = $request->[REQ_TIMER];
      if (delete $heap->{timer_to_request}->{$alarm_id}) {
        $kernel->alarm_remove( $alarm_id );
      }

      _respond($heap, $request_id, $request);
    }
  }
}

#------------------------------------------------------------------------------
# Determine whether a host is in a no-proxy list.

sub _in_no_proxy {
  my ($host, $no_proxy) = @_;
  foreach my $no_proxy_domain (@$no_proxy) {
    return 1 if $host =~ /\Q$no_proxy_domain\E$/i;
  }
  return 0;
}

#------------------------------------------------------------------------------
# Generate a hex dump of some input.  This is not a POE function.

sub _hexdump {
  my $data = shift;

  my $dump;
  my $offset = 0;
  while (length $data) {
    my $line = substr($data, 0, 16);
    substr($data, 0, 16) = '';

    my $hexdump  = unpack 'H*', $line;
    $hexdump =~ s/(..)/$1 /g;

    $line =~ tr[ -~][.]c;
    $dump .= sprintf( "%04x %-47.47s - %s\n", $offset, $hexdump, $line );
    $offset += 16;
  }

  return $dump;
}

#------------------------------------------------------------------------------
# Post an error message.  This is not a POE function.

sub _post_error {
  my ($request, $message) = @_;

  my $nl = "\n";

  my $host = $request->[REQ_HOST];
  my $port = $request->[REQ_PORT];

  my $response = HTTP::Response->new(500);
  $response->content(
    "<HTML>$nl" .
    "<HEAD><TITLE>An Error Occurred</TITLE></HEAD>$nl" .
    "<BODY>$nl" .
    "<H1>An Error Occurred</H1>$nl" .
    "500 Cannot connect to $host:$port ($message)$nl" .
    "</BODY>$nl" .
    "</HTML>$nl"
  );

  $request->[REQ_POSTBACK]->($response);
}

#------------------------------------------------------------------------------
# Generate a response, and if necessary postback. This is not a POE function.

sub _respond {
  my($heap, $request_id, $request) = @_;
  my $response = $request->[REQ_RESPONSE];
  if ($heap->{frmax}) {
    # If this page sent redirect, store response and return.
    if ($heap->{redir}->{$request_id}->{followed}) {
      $heap->{redir}->{$request_id}->{response} = $response;
      return;
    }
    else { # No redirect, or real destination => assemble chain and return
      my $tmpresponse = $response;
      while (defined $heap->{redir}->{$request_id}->{from}) {
        my $prev = $heap->{redir}->{$request_id}->{from};
        $tmpresponse->previous(delete $heap->{redir}->{$prev}->{response});
        $tmpresponse = $tmpresponse->previous();
	$request_id = $prev;
      }
    }
  }
  $request->[REQ_POSTBACK]->($response);
}

1;

__END__

=head1 NAME

POE::Component::Client::HTTP - a HTTP user-agent component

=head1 SYNOPSIS

  use POE qw(Component::Client::HTTP);

  POE::Component::Client::HTTP->spawn(
    Agent     => 'SpiffCrawler/0.90',   # defaults to something long
    Alias     => 'ua',                  # defaults to 'weeble'
    From      => 'spiffster@perl.org',  # defaults to undef (no header)
    Protocol  => 'HTTP/0.9',            # defaults to 'HTTP/1.0'
    Timeout   => 60,                    # defaults to 180 seconds
    MaxSize   => 16384,                 # defaults to entire response
    Streaming => 4096,                  # defaults to 0 (off)
		 FollowRedirects => 2   # defaults to 0 (off)
    Proxy     => "http://localhost:80", # defaults to HTTP_PROXY env. variable
    NoProxy   => [ "localhost", "127.0.0.1" ], # defs to NO_PROXY env. variable
  );

  $kernel->post( 'ua',        # posts to the 'ua' alias
                 'request',   # posts to ua's 'request' state
                 'response',  # which of our states will receive the response
                 $request,    # an HTTP::Request object
               );

  # This is the sub which is called when the session receives a
  # 'response' event.
  sub response_handler {
    my ($request_packet, $response_packet) = @_[ARG0, ARG1];

    # HTTP::Request
    my $request_object  = $request_packet->[0];

    # HTTP::Response
    my $response_object = $response_packet->[0];

    my $stream_chunk;
    if (! defined($response_object->content)) {
      $stream_chunk = $response_packet->[1];
    }

    print( "*" x 78, "\n",
           "*** my request:\n",
           "-" x 78, "\n",
           $request_object->as_string(),
           "*" x 78, "\n",
           "*** their response:\n",
           "-" x 78, "\n",
           $response_object->as_string(),
         );

    if (defined $stream_chunk) {
      print( "-" x 40, "\n",
             $stream_chunk, "\n"
           );
    }

    print "*" x 78, "\n";
  }

=head1 DESCRIPTION

POE::Component::Client::HTTP is an HTTP user-agent for POE.  It lets
other sessions run while HTTP transactions are being processed, and it
lets several HTTP transactions be processed in parallel.

If POE::Component::Client::DNS is also installed, Client::HTTP will
use it to resolve hosts without blocking.  Otherwise it will use
gethostbyname(), which may have performance problems.

HTTP client components are not proper objects.  Instead of being
created, as most objects are, they are "spawned" as separate sessions.
To avoid confusion (and hopefully not cause other confusion), they
must be spawned with a C<spawn> method, not created anew with a C<new>
one.

PoCo::Client::HTTP's C<spawn> method takes a few named parameters:

=over 2

=item Agent => $user_agent_string

=item Agent => \@list_of_agents

If a UserAgent header is not present in the HTTP::Request, a random
one will be used from those specified by the C<Agent> parameter.  If
none are supplied, POE::Component::Client::HTTP will advertise itself
to the server.

C<Agent> may contain a reference to a list of user agents.  If this is
the case, PoCo::Client::HTTP will choose one of them at random for
each request.

=item Alias => $session_alias

C<Alias> sets the name by which the session will be known.  If no
alias is given, the component defaults to "weeble".  The alias lets
several sessions interact with HTTP components without keeping (or
even knowing) hard references to them.  It's possible to spawn several
HTTP components with different names.

=item CookieJar => $cookie_jar

C<CookieJar> sets the component's cookie jar.  It expects the cookie
jar to be a reference to a HTTP::Cookies object.

=item From => $admin_address

C<From> holds an e-mail address where the client's administrator
and/or maintainer may be reached.  It defaults to undef, which means
no From header will be included in requests.

=item MaxSize => OCTETS

C<MaxSize> specifies the largest response to accept from a server.
The content of larger responses will be truncated to OCTET octets.
This has been used to return the <head></head> section of web pages
without the need to wade through <body></body>.

=item NoProxy => [ $host_1, $host_2, ..., $host_N ]

=item NoProxy => "host1,host2,hostN"

C<NoProxy> specifies a list of server hosts that will not be proxied.
It is useful for local hosts and hosts that do not properly support
proxying.  If NoProxy is not specified, a list will be taken from the
NO_PROXY environment variable.

  NoProxy => [ "localhost", "127.0.0.1" ],
  NoProxy => "localhost,127.0.0.1",

=item Protocol => $http_protocol_string

C<Protocol> advertises the protocol that the client wishes to see.
Under normal circumstances, it should be left to its default value:
"HTTP/1.0".

=item Proxy => [ $proxy_host, $proxy_port ]

=item Proxy => $proxy_url

=item Proxy => $proxy_url,$proxy_url,...

C<Proxy> specifies one or more proxy hosts that requests will be
passed through.  If not specified, proxy servers will be taken from
the HTTP_PROXY (or http_proxy) environment variable.  No proxying will
occur unless Proxy is set or one of the environment variables exists.

The proxy can be specified either as a host and port, or as one or
more URLs.  Proxy URLs must specify the proxy port, even if it is 80.

  Proxy => [ "127.0.0.1", 80 ],
  Proxy => "http://127.0.0.1:80/",

C<Proxy> may specify multiple proxies separated by commas.
PoCo::Client::HTTP will choose proxies from this list at random.  This
is useful for load balancing requests through multiple gateways.

  Proxy => "http://127.0.0.1:80/,http://127.0.0.1:81/",

=item Streaming => OCTETS

C<Streaming> changes allows Client::HTTP to return large content in
chunks (of OCTETS octets each) rather than combine the entire content
into a single HTTP::Response object.

By default, Client::HTTP reads the entire content for a response into
memory before returning an HTTP::Response object.  This is obviously
bad for applications like streaming MP3 clients, because they often
fetch songs that never end.  Yes, they go on and on, my friend.

When C<Streaming> is set to nonzero, however, the response handler
receives chunks of up to OCTETS octets apiece.  The response handler
accepts slightly different parameters in this case.  ARG0 is also an
HTTP::Response object but it does not contain response content,
and ARG1 contains a a chunk of raw response
content, or undef if the stream has ended.

  sub streaming_response_handler {
    my $response_packet = $_[ARG1];
    my ($response, $data) = @$response_packet;
    print SAVED_STREAM $data if defined $data;
  }

=item FollowRedirects => $number_of_hops_to_follow

C<FollowRedirects> specifies how many redirects (e.g. 302 Moved) to
follow.  If not specified defaults to 0, and thus no redirection is
followed.  This maintains compatibility with the previous behavior,
which was not to follow redirects at all.

If redirects are followed, a response chain should be built, and can
be accessed through $response_object->previous(). See HTTP::Response
for details here.

=item Timeout => $query_timeout

C<Timeout> specifies the amount of time a HTTP request will wait for
an answer.  This defaults to 180 seconds (three minutes).

=back

Sessions communicate asynchronously with PoCo::Client::HTTP.  They
post requests to it, and it posts responses back.

Requests are posted to the component's "request" state.  They include
an HTTP::Request object which defines the request.  For example:

  $kernel->post( 'ua', 'request',           # http session alias & state
                 'response',                # my state to receive responses
                 GET 'http://poe.perl.org', # a simple HTTP request
                 'unique id',               # a tag to identify the request
                 'progress',                # an event to indicate progress
               );

Requests include the state to which responses will be posted.  In the
previous example, the handler for a 'response' state will be called
with each HTTP response.  The "progress" handler is optional and if
installed, the component will provide progress metrics (see sample
handler below).

In addition to all the usual POE parameters, HTTP responses come with
two list references:

  my ($request_packet, $response_packet) = @_[ARG0, ARG1];

C<$request_packet> contains a reference to the original HTTP::Request
object.  This is useful for matching responses back to the requests
that generated them.

  my $http_request_object = $request_packet->[0];
  my $http_request_tag    = $request_packet->[1]; # from the 'request' post

C<$response_packet> contains a reference to the resulting
HTTP::Response object.

  my $http_response_object = $response_packet->[0];

Please see the HTTP::Request and HTTP::Response manpages for more
information.

There's also a pending_requests_count state that returns the number of
requests currently being processed.  To receive the return value, it
must be invoked with $kernel->call().

  my $count = $kernel->call('ua' => 'pending_requests_count');

The example progress handler shows how to calculate a percentage of
download completion.

  sub progress_handler {
    my $gen_args  = $_[ARG0];    # args passed to all calls
    my $call_args = $_[ARG1];    # args specific to the call

    my $req = $gen_args->[0];    # HTTP::Request object being serviced
    my $tag = $gen_args->[1];    # Request ID tag from.
    my $got = $call_args->[0];   # Number of bytes retrieved so far.
    my $tot = $call_args->[1];   # Total bytes to be retrieved.
    my $oct = $call_args->[2];   # Chunk of raw octets received this time.

    my $percent = $got / $tot * 100;

    printf(
      "-- %.0f%% [%d/%d]: %s\n", $percent, $got, $tot, $req->uri()
    );
  }

=head1 ENVIRONMENT

POE::Component::Client::HTTP uses two standard environment variables:
HTTP_PROXY and NO_PROXY.

HTTP_PROXY sets the proxy server that Client::HTTP will forward
requests through.  NO_PROXY sets a list of hosts that will not be
forwarded through a proxy.

See the Proxy and NoProxy constructor parameters for more information
about these variables.

=head1 SEE ALSO

This component is built upon HTTP::Request, HTTP::Response, and POE.
Please see its source code and the documentation for its foundation
modules to learn more.  If you want to use cookies, you'll need to
read about HTTP::Cookies as well.

Also see the test program, t/01_request.t, in the PoCo::Client::HTTP
distribution.

=head1 BUGS

HTTP/1.1 requests are not supported.

The following spawn() parameters are accepted but not yet implemented:
Timeout.

There is no support for CGI_PROXY or CgiProxy.

=head1 AUTHOR & COPYRIGHTS

POE::Component::Client::HTTP is Copyright 1999-2002 by Rocco Caputo.
All rights are reserved.  POE::Component::Client::HTTP is free
software; you may redistribute it and/or modify it under the same
terms as Perl itself.

Rocco may be contacted by e-mail via rcaputo@cpan.org.

=cut
