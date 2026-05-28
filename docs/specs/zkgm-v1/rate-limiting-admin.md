# Rate Limiting and Admin

## Rate Limiting

The proxy owns per-denom token buckets. Each bucket tracks `Capacity`,
`Available`, `RefillRate`, and `LastRefill`. Refill is linear over elapsed
seconds and capped at capacity.

`RateLimit` returns nil when the global kill switch is enabled, the amount is
nil, or no bucket is configured for the denom. Otherwise it refills the bucket
using block time and then charges the requested amount.

`TokenOrderV2` verification charges rate limits for `INITIALIZE`, `ESCROW`,
and `UNESCROW`. The public `Send` and `SendRaw` entry points do not charge by
themselves.

## Admin Operations

| Function | Purpose | Auth |
|----------|---------|------|
| `SetAdmin` | Sets or transfers the admin. Existing admin must authorize transfers. | Origin call; existing admin (or bootstrap when unset). |
| `Pause` | Sets `paused = true`. | Admin. |
| `Unpause` | Sets `paused = false`. | Admin. |
| `SetBucketConfig` | Creates or updates a token bucket. Writes the bucket map directly; does not call the impl-gated `SetTokenBucket` helper. | Admin. |
| `SetRateLimitDisabled` | Toggles the global rate-limit kill switch. | Admin. |

## Pause Semantics

Paused state affects public send and receive paths differently depending on
the entry point:

| Entry point when paused | Result |
|-------------------------|--------|
| `Send`, `SendRaw` | panic |
| `OnRecvPacket` | failure ack returned to core |
| `OnIntentRecvPacket` | panic |
| `Ack`, `Timeout` callbacks | no check; proceed normally |

Ack and timeout callbacks intentionally ignore the pause flag so in-flight
packets can still settle while new traffic is suspended.
