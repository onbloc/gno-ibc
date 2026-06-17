# ZKGM Test Loader Removal

## Context

ZKGM previously used dedicated test loader realms to bootstrap scenario tests.
After production bootstrap moved to `v1.Register` and v1 implementation
construction moved behind `impl.New`, those loaders made scenario tests exercise
a different active implementation path from production.

## Decision

Remove `testing/loader` and `testing/loader_denyimpl`.

Scenario filetests now call `impl.Register(cross(cur))` explicitly. Tests that
need to call v1 implementation methods directly create a local harness with
`impl.New(cross(cur))` before registration, then register v1 so proxy state is
owned by the production implementation path.

The negative allowlist scenario now bootstraps an explicit configuration from
the v1 realm that excludes `/v1` from `allowedImpls`, preserving coverage for
the failure path without a dedicated loader package.

## Alternatives Considered

Keeping test loaders was rejected because it preserved a non-production
`implPath` in scenario tests.

Adding production allowlist entries for test helpers was rejected because test
realms must not become production trust anchors.

Rewriting every direct impl harness into full proxy/core transactions was
rejected as too broad for this refactor; the direct harnesses still cover useful
low-level settlement behavior.

## Consequences

Scenario tests report `gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1` as the
active implementation path.

The remaining `allowedImpls` coverage is explicit and upgrade/recovery-shaped
instead of being coupled to loader package initialization.
