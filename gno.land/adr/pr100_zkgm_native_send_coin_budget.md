# ZKGM Native Send Coin Budget

## Context

ZKGM send verification received the user's native `SentCoins` as one immutable
`chain.Coins` value and passed it unchanged through batch and forward verify
recursion. Each native TokenOrder child then checked that the full sent coin
matched its own `BaseAmount`.

That made a batch with multiple native TokenOrders able to verify against the
same single deposit more than once. Each verified child also increased
`channelBalanceV2`, so escrow accounting could exceed the native funds actually
held by the ZKGM proxy realm.

## Decision

Create one mutable `sentCoinBudget` at the root `Send` entry point from the
parsed `SentCoins`. Thread the budget pointer through `dispatchVerify`,
`verifyBatch`, `verifyForward`, and `verifyTokenOrderV2`.

Native TokenOrder verify branches consume their `BaseAmount` from the budget by
denom before increasing channel balance. Voucher branches continue to burn
vouchers and do not touch the native budget. After recursive verification
returns to `Send`, assert that the budget is fully drained.

## Alternatives Considered

Keeping the previous exact-match check was rejected because sibling native
orders can reuse the same deposit.

Using a map keyed by denom was rejected in favor of a slice copy of
`chain.NewCoins` output. The budget is transient and small, and the slice keeps
the normalized coin representation without introducing map iteration concerns.

Moving checks to ack, timeout, or settlement paths was rejected because all of
those paths trust `channelBalanceV2`; the accounting must be correct when it is
credited.

## Consequences

Multiple native orders in a batch or forward tree now require total deposited
coins to match total native consumption exactly. Over-claims fail during
consume; under-consumption fails at the root drain check.

Multi-denom native deposits are supported by independent per-denom consumption.
Mixed native and voucher batches remain valid because voucher burns do not
consume native budget.
