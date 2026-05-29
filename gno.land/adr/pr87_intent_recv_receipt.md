# Intent Recv Receipt and Market-Maker Fill

## Context

Issue #84 identified two regressions in the v1 IBC/ZKGM intent receive path.
Core did not write a receipt for `IntentPacketRecv`, so duplicate intent
receives could replay the application callback. ZKGM also ignored the `intent`
flag for token orders, so the destination protocol path could mint or release
protocol funds instead of requiring a market maker fill.

Union's receive flow records the packet receipt before the module callback for
both proven and intent receive. The ZKGM module then treats an only-maker result
as a revert, rolling back the whole tx and leaving proven receive available.

## Decision

`IntentPacketRecv` now uses the same receipt and synchronous acknowledgement
commit path as `PacketRecv`. The app intent callback returns
`RecvPacketResult`, and core commits returned success/failure acknowledgements.

ZKGM threads the `intent` flag into token-order execution. Intent token orders
use a market-maker fill branch for voucher quote tokens only: the implementation
owns those GRC20 ledgers and can transfer maker funds directly to the receiver.
Native and unknown quote tokens return `ACK_ERR_ONLY_MAKER`; `IntentRecv`
panics on that result after dispatch returns so the tx rolls back.

## Alternatives Considered

Keeping intent receive receiptless was rejected because it has no core replay
guard and leaves source-side timeout evidence inconsistent with proven receive.

Using protocol fill for intent token orders was rejected because it spends
destination protocol funds and breaks the source-side market-maker
reimbursement model.

Supporting native market-maker funding in this change was deferred because Gno
does not expose a native `transferFrom` equivalent. Pulling native funds from
the maker requires extending the core intent surface to thread sent coins.

## Consequences

Intent receive is now idempotent at the core receipt layer and commits the same
acknowledgement evidence as proven receive when the module succeeds.

Voucher market-maker fills move maker balances to receivers without minting,
setting token origin, or touching channel balances. Unsupported maker fills
revert the intent transaction and can still be handled by proven receive.
