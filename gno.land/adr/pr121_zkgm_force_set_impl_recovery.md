# ZKGM ForceSetImpl Recovery

## Context

The ZKGM proxy tracks three pieces of implementation state:

* `impl`, the implementation used by dispatch.
* `implPath`, the runtime-verified package path of the registered implementation realm.
* `allowedImpls`, additional implementation realms recognized by the proxy.

`UpdateImpl` can safely bind `implPath` because it derives the path from
`cur.Previous().PkgPath()`. `ForceSetImpl` is an administrative recovery path
that accepts a `ZkgmImpl` value, but it cannot independently determine the
owning realm path for that value.

To maintain consistency between the active implementation, its registered path,
and the allowlist, recovery operations need to update these values in a way that
avoids stale state and preserves the expected registration flow.

The v0 implementation singleton previously used `ImplPath() != ""` to determine
whether initialization had already occurred. Recovery operations that clear
`implPath` require a separate mechanism for tracking initialization state.

## Decision

`ForceSetImpl` now clears `implPath` and replaces `allowedImpls`.

For a non-nil replacement implementation, the allowlist must be non-empty. The
replacement implementation's realm path should be included so that it can later
call `UpdateImpl` and re-establish a runtime-verified `implPath`.

Passing `newImpl == nil` remains supported and intentionally clears the
implementation, path, and allowlist.

The proxy now tracks a monotonic `bootstrapped` flag. `UpdateImpl` sets this
flag when an implementation is installed. `ForceSetImpl` does not modify it.

The v0 implementation singleton now uses `bootstrapped` rather than
`ImplPath() != ""` to determine whether initialization has already occurred.

## Alternatives Considered

### Keep the existing `implPath`

Rejected because it can leave configuration state inconsistent with the
currently installed implementation and may cause status-reporting APIs to
present outdated information.

### Add an admin-supplied `newImplPath`

Rejected because the provided path cannot be independently verified against the
implementation value being installed. The runtime registration flow already
provides a verified mechanism for establishing the implementation path.

### Use `implPath` as the singleton initialization indicator

Rejected because `implPath` represents the currently verified implementation
path, while initialization state is a separate concern. A dedicated
`bootstrapped` flag more accurately models initialization status.

## Consequences

Recovery operations reset the registered implementation path and replace the
allowlist as part of the implementation transition process.

Replacement implementations must be accompanied by at least one allowlisted
implementation path. Until registration is completed through `UpdateImpl`,
`ImplPath()` and `GetConfig()` report an empty implementation path.

Initialization state remains preserved across recovery operations through the
`bootstrapped` flag, ensuring that components relying on initialization status
continue to behave consistently.
