# ZKGM Explicit V1 Register

## Context

ZKGM used a production `v1/loader` package whose `init` function installed the
v1 implementation and registered the proxy as an IBC core app. Light clients in
this repository use an explicit `Register(cur realm)` entrypoint instead, so
ZKGM had a different deployment model and an extra production bootstrap realm.

The loader split also meant production callbacks from `v1` were authorized
through `allowedImpls`: the registered `implPath` was `v1/loader`, while the
callable implementation realm was `v1`.

ADR pr113 intentionally kept test helper realms out of the production trust set
by introducing dedicated test loaders. A follow-up refactor removed those test
loaders as well, so scenario tests now register v1 explicitly.

## Decision

Move production bootstrap into `gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1`
as `Register(cur realm)`.

`Register` installs a fresh v1 implementation through `zkgm.UpdateImpl`,
registers the proxy IBC app with core, and rejects a second bootstrap if ZKGM
is already bootstrapped.

Remove the production `v1/loader` package. Production deployment now follows
the same shape as the light clients: add the implementation package, then call
its `Register` function.

Use `v1` as the production implementation trust anchor. `ProductionImplPath`
returns that path, while `ProductionLoaderPath` remains only as a compatibility
alias.

Allow bootstrap with an empty `allowedImpls` list. Since `implPath` is now
`v1`, v1 callbacks are authorized by the `implPath` branch. The `allowedImpls`
branch remains for upgrades and explicit recovery-style tests, not for scenario
test loaders.

## Consequences

Production no longer depends on package `init` side effects for ZKGM
registration.

The production trust set no longer includes `v1/loader`, and production v1
callbacks no longer depend on `allowedImpls`.

Scenario tests no longer rely on `testing/loader` or `testing/loader_denyimpl`.
Tests that need low-level direct impl method calls construct a v1 harness before
calling `v1.Register`, while normal scenarios call `v1.Register` directly.

Any live-chain deployment or smoke tooling that previously added
`v1/loader` must instead call `v1.Register`.
