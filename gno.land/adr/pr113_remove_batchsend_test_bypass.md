# Remove BatchSend Test Bypass

> Superseded in part by `pr123_zkgm_explicit_v1_register.md`: the dedicated
> production loader was removed, but the test-loader trust isolation described
> here remains in force.

## Context

`zkgm.BatchSend` had a production-code carve-out for two test helper realms:
`gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/e2e` and
`gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/realcometbls`. Those helpers
inject pre-built packets for scenario filetests, but the hard-coded bypass meant
the production entrypoint had two authorization rules: the normal
`requireImplCaller` rule and a test-only exception.

The production loader authorizes only core, proxy, loader, and impl realms. The
test helper realms still need to call `BatchSend` in scenario stores, but they
must not be added to the production trust set.

The test loader must install the same impl instance as the production loader.
That exposes a second bootstrap boundary: `impl.GetInstance` used to admit only
the production loader, so a replacement test loader could not obtain the impl
instance unless the instance factory also recognized the bootstrap state.

This also revisits the forward receive guard from the PR91 follow-up. The
existing impl-unit forward test drives the full `PacketRecv -> executeForward ->
BatchSend` frame, but it installs the impl from package `impl`, so authorization
passes via `implPath == impl`. It is a useful wiring smoke, but not an
integration proof for the `allowedImpls` branch.

## Decision

Delete the test-only bypass and make `BatchSend` always call
`requireImplCaller`.

Add a dedicated scenario test loader at
`gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/loader`. It installs the same impl
as the production loader, registers the core app, and sets `allowedImpls` to the
production set plus the e2e and realcometbls helper realms. Only scenarios that
call helper `BatchSend` import this test loader. Because filetest imports are
initialized at package granularity, e2e BatchSend scenarios live in a separate
scenario package from e2e receive scenarios that keep the production loader.
The realcometbls helper `BatchSend` scenarios are split the same way.

The impl instance constructor keeps the production loader as the canonical
post-bootstrap caller, but allows any caller only while no impl has been
installed yet. This mirrors the existing `UpdateImpl` bootstrap window without
hard-coding test package paths into production code.

Add a separate deny-impl loader for the negative forward scenario. It installs
the impl from a non-impl realm but omits the impl pkgpath from `allowedImpls`,
so a forward child `BatchSend` must fail closed.

Move the genuine forward `allowedImpls` integration proof to scenario filetests,
where scenario packages have isolated stores and can import a loader realm
without creating an impl import cycle. Keep the impl-unit forward test as a
documented wiring smoke.

The forward scenario reconstructs the expected child packet in the e2e helper
realm. It clones the `uint256` path through an immutable decimal string before
calling path helpers, because a `z.Forward` struct built in the scenario realm
contains a cross-realm pointer field that is readonly-tainted when observed from
the e2e helper realm.

The impl native refund unit test still calls `e2e.BatchSend` directly without a
loader import. It therefore widens its local inline `allowedImpls` setup to
include the e2e helper realm.

## Alternatives Considered

Adding an exported test setup function to append or extend `allowedImpls` was
rejected. `UpdateImpl` replaces the allowed list, and a new append API would be
production surface that exists only for tests.

Adding the helper realms to the production loader was rejected because it would
trust test packages in deployed production configuration.

Adding `testing/loader` and `testing/loader_denyimpl` to a `GetInstance`
allow-list was rejected for the same reason as the removed `BatchSend` bypass:
it would reintroduce test package paths into production authorization logic.
The generic bootstrap-only exception is tied to empty impl state instead of to
test identities.

Reworking the impl-unit forward test to prove the `allowedImpls` branch was
rejected. A loader that imports impl creates an import cycle when blank-imported
from package `impl`, `UpdateImpl` is gated once `allowedImpls` is non-empty, and
the proxy reset helper is private to package `zkgm`.

Using a second entrypoint on the test loader for the negative case was rejected
because after loader init, the loader's own pkgpath is not in its allowed list;
a second `UpdateImpl` from that realm would be rejected by the caller gate.

## Consequences

`BatchSend` now has one uniform authorization rule in production code.

The two helper realms are authorized only in scenario stores that explicitly
import the test loader. The production loader's trust set remains unchanged.

Forward receive authorization has a scenario-tier positive and negative guard
for the `allowedImpls` branch. The negative guard lives in its own scenario
package so the deny-impl loader does not initialize in the same store as the
positive test loader. The impl-unit test remains valuable for frame wiring, but
no longer implies branch coverage it does not provide.

`GetInstance` now has a bootstrap window that is intentionally aligned with the
current fail-open `UpdateImpl` bootstrap behavior. If `UpdateImpl` is made
fail-closed later, the two bootstrap policies should be reviewed together.

The gnokey smoke harness now uses the test loader so it can retain
BatchSend-based qeval coverage. As a result, it no longer executes
`v0/loader.init()` on a live dev chain. The production loader path remains
covered by `gno test` and production-loader scenario filetests; a future
follow-up can add a minimal production-loader smoke that qevals
`zkgm.ImplPath()` and `zkgm.AllowedImpls()` if live-chain loader coverage is
needed.
