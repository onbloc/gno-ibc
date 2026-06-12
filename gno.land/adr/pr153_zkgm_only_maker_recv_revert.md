# ZKGM Receive Handling Update

## Context

Some receive paths did not handle retry-required outcomes consistently, which could cause packet processing results to be recorded differently than intended in certain situations.

In addition, malformed response data could affect downstream acknowledgement processing.

## Decision

The receive handling logic was aligned so that retry-required outcomes abort processing and remain eligible for retry.

CALL receiver panics now produce failure acknowledgements; only-maker receive aborts are reserved for token-order no-maker outcomes.

Acknowledgement handling was also updated to treat malformed responses as failures, ensuring downstream processing behaves consistently.

Existing error propagation behavior for internal handlers remains unchanged.

## Alternatives Considered

Modifying only lower-level execution helpers was rejected because it would reduce consistency across the overall processing flow.

Limiting the change to a subset of receive paths was also rejected because it would not fully address the issue.

Ignoring all acknowledgement errors was rejected because some errors indicate invariant violations that should continue to surface.

## Consequences

Retry-required outcomes no longer result in finalized processing and can be retried safely.

Malformed responses are handled consistently, improving the robustness of acknowledgement processing.

The behavior of lower-level execution helpers remains unchanged, preserving compatibility with existing logic and tests.
