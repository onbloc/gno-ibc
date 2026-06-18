# ZKGM V1 Impl Constructor

## Context

The ZKGM proxy owns the active implementation pointer through `UpdateImpl`.
Production registration currently installs the v1 implementation from the v1
realm, but the concrete value is backed by a package-level `instance` singleton
inside `gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1`.

That singleton keeps implementation object ownership inside the v1 package
rather than making each bootstrap or upgrade path explicitly hand a fresh
implementation object to the proxy. It also leaves `GetInstance` as a public
post-bootstrap path for obtaining a callable v1 implementation object.

The implementation business logic should remain in the v1 realm. Moving
`ZkgmV1` methods into the proxy realm would collapse the replaceable
implementation boundary.

## Decision

Remove the package-level v1 implementation singleton.

Expose `impl.New(cur realm) zkgm.ZkgmImpl` as the constructor for fresh v1
implementation objects. The constructor preserves the existing bootstrap gate:
before the proxy is bootstrapped, proxy-subpackage loaders may construct the
implementation; after bootstrap, only `zkgm.ProductionImplPath()` may construct
another v1 implementation object.

Update production registration and test loaders to install `impl.New(cross(cur))`
through `zkgm.UpdateImpl`. The proxy continues to own the active `ZkgmImpl`
pointer and allowed implementation paths.

## Alternatives Considered

### Keep `GetInstance`

Rejected because the singleton is no longer needed once the proxy owns the
active implementation pointer. Keeping it would preserve an avoidable public
path to the same callable implementation object.

### Move `ZkgmV1` into the proxy realm

Rejected because it would make v1 no longer a replaceable implementation layer.
The proxy should own the selected implementation pointer, not the v1 business
logic.

### Make `New` unrestricted

Rejected because foreign realms could obtain callable implementation objects
after bootstrap. The existing post-bootstrap protection remains required.

## Consequences

The v1 implementation realm still owns the `ZkgmV1` type and methods, while the
proxy realm remains the owner of the active implementation pointer.

Test loaders continue to exercise the `allowedImpls` branch by constructing and
installing fresh v1 implementation objects with their existing allowlists.

Foreign realms cannot obtain a v1 implementation object through the constructor
after bootstrap, and direct foreign allocation of `ZkgmV1` remains blocked by
realm allocation rules.
