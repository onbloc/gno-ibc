# ZKGM Local GRC20 Asset Support

## Context

ZKGM already mints inbound IBC vouchers as GRC20 tokens, but locally-originating
send escrow only understood two asset classes: `ibc/` vouchers and native banker
coins. A registered local GRC20 therefore fell through to the native coin
budget path and could not be sent, because GRC20 balances are not attached to
`OriginSend`.

The gno-realms transfer app has the GRC20 escrow mechanics we need, but it is an
ICS-20 app with different packet data, denom tracing, and callback semantics.
ZKGM uses Union's TokenOrderV2 ABI flow, so importing the transfer app would add
an incompatible protocol rather than local GRC20 support.

Two risks shape the implementation. First, `grc20reg.Register` can overwrite a
key, so reclassifying a denom at refund or release time can choose a different
asset backend than the one used at escrow time. Second, `grc20.RealmTeller`
binds operations to the current realm frame, so proxy-held escrow must be moved
from proxy realm functions, not from implementation-local helpers.

## Decision

Add a third ZKGM asset class for registered local GRC20 tokens. The classifier
checks `ibc/` vouchers first, then `grc20reg.Get`, and treats anything else as a
native banker denom.

Persist the asset class write-once by denom when INITIALIZE or ESCROW verifies
and successfully escrows the asset. Refund and release paths consult the
persisted class instead of re-reading the registry.

Keep escrow funds at the ZKGM proxy realm. Add proxy-gated `EscrowGRC20` and
`ReleaseGRC20` functions next to `ReleaseNative`, protected by the same
implementation-realm authorization boundary. Both functions construct
`tok.RealmTeller(0, cur)` with the proxy's own `cur`.

Use an approve-first UX for local GRC20 sends. Users approve `ProxyAddress()` as
spender, and send verification pulls tokens with `TransferFrom`. The local
GRC20 branch does not consume native sent-coin budget, so any stray attached
native coins are still rejected by the root budget drain check.

Do not introduce a GRC20 alias format. ZKGM carries token identifiers as bytes,
so slash-bearing registry keys can be transported directly; the ICS-20
slash-path constraint does not apply here.

## Alternatives Considered

Importing the gno-realms ICS-20 transfer app was rejected because it implements
a different wire protocol and app interface from ZKGM.

Reclassifying denoms dynamically at release time was rejected because registry
overwrites could cause native escrow to be released as GRC20, or local GRC20
escrow to be released as native.

Moving GRC20 teller operations into the implementation realm was rejected
because the teller's spender and source account are frame-sensitive. Escrow and
release must both execute in the proxy frame that owns the escrow address.

Adding alias encoding for GRC20 keys was rejected until a concrete ZKGM
counterparty requires it.

## Consequences

ZKGM can now escrow and release registered local GRC20 tokens without minting or
burning them. Vouchers keep their burn/mint behavior, and native coins keep the
banker escrow path.

Local GRC20 sends require prior approval for the proxy address. Missing approval
fails send verification before channel balance is increased.

Persisted class state makes refund and timeout behavior stable even if a denom
is later registered or overwritten in `grc20reg`.
