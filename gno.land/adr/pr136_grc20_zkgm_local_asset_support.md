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
and successfully escrows the asset. The class record lives in the proxy realm
through `RecordAssetClass` and `GetAssetClass`, next to the escrow funds and the
channel balance, so it survives implementation upgrades. Refund and release
paths consult the persisted class instead of re-reading the registry.

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

## Follow-up Hardening

Review found that persisting only the asset class is not enough for local GRC20
escrow. `grc20reg.Register` can overwrite an existing key, so a release that
re-resolves the key could transfer a different token than the one originally
escrowed.

The proxy now pins the concrete `*grc20.Token` for each local GRC20 denom the
first time it escrows or releases that denom. Later escrow and release calls use
the pinned token instead of re-reading `grc20reg`, so registry overwrite cannot
substitute the escrow backend for that denom.

Send verification also rejects zero base amounts before reaching the proxy
GRC20 path, keeping local GRC20 behavior aligned with normal validation errors
instead of proxy panics.

Finally, escrow now compares the live asset class with the write-once recorded
class. If a denom's class changes after its first escrow, verification returns
an error instead of silently escrowing one asset type and releasing another.

The asset-class record was initially package state in the swappable
implementation realm. `UpdateImpl` replaces that realm, so a local GRC20 order
in flight across an upgrade would find an empty class map at release time, fall
back to the native path, and try to release a native coin the proxy does not
hold. The record now lives in the proxy realm alongside the pinned token and the
channel balance, both of which already survive an implementation swap.

Native release also no longer relies on a raw panic for missing escrow.
`ReleaseNative` checks the proxy escrow balance and returns an error when it is
insufficient, and `sendNative` propagates that error so the caller converts it
into an `execFatal` rollback. `dispatchExecute` recovers ordinary panics into a
failure ack without rolling back state, so a raw panic from a failed release
would have committed an already-applied channel balance debit. The UNESCROW
receive path now verifies the channel balance before release and debits it only
after release succeeds, so a failed release leaves the balance intact.
