# Intent Call Fail Closed

## Context

The system supports two receive modes:

* Intent receive, which allows optimistic settlement by a market maker.
* Proven receive, which processes packets after standard verification.

Token-order operations already define explicit behavior on the intent path and
can safely defer processing when settlement conditions are not met.

Call operations do not currently have defined intent-settlement semantics.
Although the interface includes a dedicated intent-call handler, its behavior
and receiver expectations have not been specified.

As a result, call processing on the intent path lacks a well-defined execution
model.

## Decision

Call operations are not processed on the intent path.

When a call instruction is encountered during intent receive, processing returns
`ACK_ERR_ONLY_MAKER`, causing the packet to be deferred until proven receive.

The intent flag is propagated through call execution so that both direct calls
and calls contained within batches follow the same behavior.

Existing validation and protocol-specific error handling remain unchanged and
continue to take precedence where applicable.

## Alternatives Considered

### Route calls to the intent-call handler

Rejected because intent-call semantics are not currently defined.

Enabling intent-call dispatch would introduce a new execution path without a
clear specification of settlement behavior or receiver expectations.

### Return a standard failure acknowledgement

Rejected because call processing should remain eligible for handling through the
proven receive path.

### Remove the intent-call interface

Rejected because the interface may be used by a future design that introduces
explicit intent-call semantics.

## Consequences

Calls are processed only through proven receive.

Intent receive no longer executes call operations directly and instead defers
them until proven receive.

Batches containing calls inherit the same behavior.

The intent-call interface remains available for future designs but is not
currently used.
