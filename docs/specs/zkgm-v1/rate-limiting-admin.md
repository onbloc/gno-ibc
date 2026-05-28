# Rate Limiting

The proxy owns per-denom token buckets. Each bucket tracks `Capacity`,
`Available`, `RefillRate`, and `LastRefill`. Refill is linear over elapsed
seconds and capped at capacity.

`RateLimit` returns nil when the global kill switch is enabled, the amount is
nil, or no bucket is configured for the denom. Otherwise it refills the bucket
using block time and charges the requested amount.

TokenOrderV2 verification charges rate limits for `INITIALIZE`, `ESCROW`, and
`UNESCROW`. The public `Send` and `SendRaw` entry points do not charge by
themselves.

Admin functions configure rate limiting:

| Function | Behavior |
|----------|----------|
| `SetBucketConfig` | Creates or updates a bucket for a denom. |
| `SetRateLimitDisabled` | Toggles the global rate-limit kill switch. |

`SetBucketConfig` writes directly to the token bucket map because admin owns
configuration. It does not call the impl-gated `SetTokenBucket` helper.

## Admin Operations

| Function | Behavior |
|----------|----------|
| `SetAdmin` | Sets or transfers the admin. Requires origin call. Existing admin must authorize transfers. |
| `Pause` | Sets `paused = true`. |
| `Unpause` | Sets `paused = false`. |
| `SetBucketConfig` | Creates or updates a token bucket. |
| `SetRateLimitDisabled` | Enables or disables the global rate-limit bypass. |

Paused state affects public send and receive paths. `Send` and `SendRaw` panic
when paused. `OnRecvPacket` returns a failure acknowledgement when paused.
`OnIntentRecvPacket` panics when paused. Ack and timeout callbacks do not check
the pause flag.
