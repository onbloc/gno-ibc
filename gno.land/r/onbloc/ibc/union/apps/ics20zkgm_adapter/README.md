Adapter realm for single-sign bridging between ICS20 (AtomOne) and ZKGM/UCS03
(Union/EVM). See https://github.com/onbloc/gno-ibc/issues/134.

- `TransferHook.OnTransferRecv` (forward, AtomOne -> EVM): registered with
  `apps/transfer` via `SetHook`. Fires after an ICS20 mint; parses the memo
  and forwards the token onward via `zkgm.Send`.
- `Zkgmable.OnZkgm` (reverse, EVM -> AtomOne): registered with `apps/ucs03_zkgm`
  via `RegisterReceiver`. Fires on a ZKGM `OP_CALL` batch child; parses the
  call data and forwards the token onward via `transfer.Send`.

## Upgradeable proxy/impl split

Mirrors `apps/ucs03_zkgm`'s proxy/impl model:

- This package (the proxy) is the stable identity — its `Adapter` struct is
  what `transfer.SetHook` and `zkgm.RegisterReceiver` see, and its address
  (`ProxyAddress`) never changes across upgrades. `Adapter`'s methods carry no
  logic; they delegate to the installed impl via `mustGetImpl()`.
- `v1/` (and any later `v2/`, ...) is a disposable impl sub-realm. It
  registers a constructor for itself in its own `init(cur realm)` via
  `RegisterImpl`, then an admin activates a registered path with
  `UpdateImpl(cur, path)` (see `upgrade.gno`).
- Persistent domain state lives in the proxy's `Store` (`store.gno`) and is
  injected into whichever impl is active, so it survives impl upgrades
  (mirrors `apps/ucs03_zkgm/store.gno`).

## Denom registry

`Store.denomConfigs` (admin-managed via `RegisterDenom`/`UnregisterDenom` in
`admin.gno`) maps an ICS20 base denom (e.g. `"uatom"`) to the data
`OnTransferRecv` needs to build an outbound ZKGM `TokenOrderV2`:

- `ZkgmChannelId`: the destination ZKGM channel toward the target EVM chain.
- `QuoteToken` / `Metadata`: the predicted EVM `ZkgmERC20` address and its
  ABI-encoded `TokenMetadata`, both computed off-chain (this realm cannot call
  the EVM `predictWrappedTokenV2` view live) and registered once per denom.

The `BaseToken` field of the instruction is *not* stored here — it's derived
at call time from the recv'd `Denom` (`denom.HashHex()`, the same grc20reg
slug `apps/transfer` registered the voucher under), so it can't go stale.

The order `Kind` is always `TOKEN_ORDER_KIND_INITIALIZE`, never `ESCROW` —
see the doc comment on `v1/impl.gno`'s `OnTransferRecv` for why (verified
against the actual EVM contract in `union-voyager`: deploy is skipped
idempotently if the wrapped token already exists).

## Async ack resolution (forward direction)

The forwarded ZKGM packet's ack/timeout arrives long after `OnTransferRecv`
returns, so the original ICS20 packet's acknowledgement can't be written
immediately. Instead of sending a brand-new refund packet (which could
itself fail to be received — see `async-ack-design-ko.md` for why that
design was discarded), the adapter defers the original packet's ack:

- `OnTransferRecv` records `PendingForward{SourceClient, Sequence}` keyed by
  the outbound ZKGM packet's commitment hash, then returns
  `transfer.ErrHookAsync` so `apps/transfer` defers the original packet's
  ack (`store.gno`, `v1/forward.gno`).
- `ResolveForward(packetHash)` is permissionless — typically called by a
  relayer once `apps/ucs03_zkgm`'s `GetSendResult` reports the packet
  resolved — and pushes the confirmed success/failure onto the original
  ICS20 packet's deferred acknowledgement via the installed
  `TransferAckResolver` (`v1/resolve.gno`).
- `TransferAckResolver` (`v1/transfer_ack_resolver.gno`) delegates to
  `apps/transfer`'s `WriteHookAck`; an admin must install it once via
  `SetTransferAckResolver`. See `async-ack-design-ko.md` for the full design.
