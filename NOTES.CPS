Title

	POE::Stage
	Message-Based Continuations
	Rocco Caputo
	http://thirdlobe.com/projects/poe-stage/

Continuations

	"... a sort of super-closure, one that remembers all the lexicals
	that were in scope when it was created, as well as remembering the
	call sequence you took to get there."  -- Dan Sugalski

Continuations

	Encapsulate Call
		Specify where to resume on return.
		Remember lexical state, so it can be restored on return.
		Are passed to subroutines as just another parameter.

	"Return" when invoked.
		Restore the caller's lexical state.
		Resume where the caller left off, maybe passing along output.

POE::Request

	Encapsulates Call
		Specifies where to resume on return.
		Remembers lexical state, so it can be restored on return.
		Are passed to methods magically (more shortly).

POE::Response

	Implicitly created when an inbound POE::Request is invoked.
		$inbound_request->return( ... );

	Restores the caller's lexical state.
	Resumes the caller at a location specified in the request.

POE::Request Example

	my $outbound_request = POE::Request->new(
		{
			stage => $target_stage_object,
			method => $target_method_name,
			args => \%maybe_some_parameters,
			on_success => \&resume_here_on_success,
			on_failure => \&or_here_on_failure,
		}
	);

POE::Response Return

	$inbound_request->return(
		{
			type => "success",  # could be "failure"
			args => \%maybe_some_return_values,
		}
	);

Multiple Resume Points

	Caller maps return types resume points

		on_success => \&resume_here_on_success,
		on_failure => \&or_here_on_failure,

	Return "type" determines which branch to take

		type => "success",

Benefits of Multiple Resume Points

	Decouples caller and callee interfaces.
		Neither end of the call needs special information about the other.
	Dynamic flow control.

Call State

	Tree-based rather than stack based.
		Requests are asynchronous.
		One request may trigger multiple sub-requests.

		Parent Request
			-> Sub Request 1
			-> Sub Request 2
			-> ...

Call State

	Asynchronous calls may be canceled before responses are returned.
	Cancelation prunes the call tree.

		$outbound_request->cancel();

		Sub-requests under the canceled request are also canceled.
		Lexical contexts are also destroyed.
		Resources stored in those contexts are automatically freed.
		Perl (not POE) GC rules apply here.

Call State

	Asynchronous replies may be out of order.

		Parent Request
			-> Sub Request 1
			-> Sub Request 2
			<- Response 1
			<- Response 2

Call State

	One request may have multiple responses.

		Parent Request
			-> Sub Request 1
			<- Response 1a
			<- Response 1b
			...

Call State

	Two kinds of response: interim and final.
	Already seen final response: return().
	Interim response: emit().

	$inbound_request->emit(
		{
			type => "status",
			args => \%some_status_values,
		}
	);

More on Emit

	Parent may want to respond to emit() without creating a new
	continuation: recall()

	$inbound_response->recall(
		{
			method => $target_method_name,
			args   => \%maybe_some_more_parameters,
		}
	);

	Simpler than POE::Request.
		Inherits target stage from original POE::Request.
		Also inherits role or return mapping.

Lexical State

	Not entire lexical state, just lexicals with certain prefixes.
	For example, state associated with an inbound request:
		$req_member @req_member %req_member
	Implemented with pad manipulation before methods are called.
	Lexical::Persistence spun off so anyone can enjoy this magic.
	Method parameters while we're at it (because we can):
		$arg_name @arg_name %arg_name

Call Tree Revisited

	Call tree is implemented by convention.
	Sub-request stored in the current request.
		my $req_subrequest = POE::Request->new( ... );
	If the current request is canceled:
		All its $req_* members destroyed.
		Triggers $req_subrequest destruction.
		Etc. down the tree branch.

Lexical State

	Activated by a :Handler sub attribute

		sub resume_here_on_success :Handler { ... }

	Or methods whose names begin with "on_".
		See next slide.

Request Roles

	my $req_subrequest = POE::Request->new(
		{
			stage   => $target_stage_object,
			method  => $target_method_name,
			args    => \%maybe_some_parameters,
			role    => "rolename",
		}
	);

	role replaces on_success and on_failure parameters.
	So how are returns routed?

Requets Roles

	Return routing is done by a method naming convention.
		"on_" . $role_name . "_" . $return_type

		sub on_rolename_success { ... }
		sub on_rolename_failure { ... }
		sub on_rolename_timeout { ... }
		etc.

	:Handler attribute implied.

Response Continuation

	POE::Request encapsulates one more lexical context.
	This one's for the caller.
		Caller can associate data with a request.
		Caller gets that data back with a response.
		Request target never sees this data.

Response Continuation

	At request time, members must be exposed into lexical space.

		my $outbound_request = POE::Request->new( ... );
		expose $outbound_request => my $prefix_member;
		$prefix_member = "this is stored in the request";

	$prefix_member is an exposed lexical representing $member within
	$outbound_request.

	Prefix is arbitrary.  Added to prevent lexical collision.

Response Continuation

	Response continuation is available when handling a response.
		Either return() or emit().

	Special rsp prefix.
		$rsp_member @rsp_member %rsp_member

	sub on_rolename_success {
		my $rsp_member; # "this is stored in the request"
		...;
	}

Standard POE::Stage Interface

	init
	... ? TODO

Standard Stages

	App
	... ? TODO

Loose Ends

	It's 05:00.
	I can't think of them right now.
	TODO

Design Goals

	Standardize the strongest, best POE design patterns.
		TIMTOWTDI didn't scale.
		Subsume the good patterns into the framework.

	Ignore backward compatibility.
		Nobody's using this yet.
		We can -Ofun rather than -Ostability at this point.

Design Goals

	More Community Involvement
		Here's a chance to improve on what you like least about POE.
		Avoid puzzling over things named "Wheel". :)

What You Can Do

	Just about anything.
		Design something.
		Implement something.
		Smash the system!
		Document stuff.
		Sieze a need and run with it.

Questions?

	Thank you.
