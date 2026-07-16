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
