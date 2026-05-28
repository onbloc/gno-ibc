# Proxy State

All durable ZKGM state lives in the proxy realm. The active implementation is
stateless apart from the package-level `ZkgmV1` singleton.

| State | Type | Purpose |
|-------|------|---------|
| `impl` | `ZkgmImpl` | Active implementation object. |
| `implPath` | `string` | Pkgpath that installed the current implementation. |
| `allowedImpls` | `[]string` | Whitelist for implementation and loader realms. Empty means bootstrap mode. |
| `paused` | `bool` | Global pause flag. |
| `gRealmAddress` | `address` | Cached proxy realm address. |
| `adminAddressStr` | `string` | Admin address string. Empty means admin bootstrap mode. |
| `receivers` | BPTree map | Registered `Zkgmable` receivers by pkgpath. |
| `tokenOrigin` | BPTree map | Wrapped denom to mint path. |
| `metadataImageOf` | BPTree map | Wrapped denom to metadata image. |
| `channelBalanceV2` | BPTree map | Escrow balance by channel, path, base token, and quote token. |
| `inFlightPackets` | BPTree map | Forwarded child packet hash to parent packet. |
| `tokenBucket` | BPTree map | Per-denom rate-limit bucket. |
| `rateLimitDisabled` | `bool` | Global rate-limit kill switch. |

The current ledger has only `channelBalanceV2`. There is no `channelBalanceV1`
store in committed code.

## Implementation Pointer

The proxy can replace its active implementation through `UpdateImpl`. The call
is allowed when `allowedImpls` is empty or the previous realm pkgpath is already
listed in `allowedImpls`. A non-nil `AllowedImpls` value replaces the whitelist.
A non-nil `Impl` value replaces the active implementation and records the caller
pkgpath in `implPath`.

The loader seeds the proxy with allowed paths for IBC core, the proxy, the
loader, and the v0 implementation. It then registers the proxy app with IBC
core under `zkgm.ProxyPkgPath()`.

`GetInstance` in the implementation realm is loader-only. Calls from any other
previous realm panic.

## Authorization Model

ZKGM uses four authorization styles.

`mustBeAuthorizedImpl(cur)` gates ledger writes. It accepts any caller whose
pkgpath is in `allowedImpls`. It protects token origin, metadata image, channel
balance, in-flight packet, token bucket setter, token bucket remover, and
`RateLimit` calls.

`requireImplCaller(cur, action)` gates proxy actions that move state or funds on
behalf of the implementation. It accepts the registered `implPath` and entries
in `allowedImpls`. It protects `WriteForwardAck` and `ReleaseNative`.

`BatchSend` is implementation-only, with explicit test realm bypasses for the
existing e2e and real CometBLS scenario packages. The bypasses are hardcoded
for the `testing/e2e` and `testing/realcometbls` package paths.

Admin operations use `mustBeAdmin`. When `adminAddressStr` is empty, bootstrap
calls are allowed. Once set, admin calls require an origin call and the origin
caller must match `adminAddressStr`.

Native `Send` and `SendRaw` require an EOA call frame. They read
`OriginSend()` only when `cur.Previous().IsUserCall()` is true and then call
`runtime.AssertOriginCall()` before using `OriginCaller()` as the ZKGM sender.
