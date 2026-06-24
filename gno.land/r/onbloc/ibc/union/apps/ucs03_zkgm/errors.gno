package zkgm

// ErrSpoofedRealm guards non-crossing (_ int, rlm realm, ...) entrypoints: the
// passed rlm must be the current crossing frame, not a forged or stale token
// replayed by a caller.
const (
	ErrSpoofedRealm             = "rlm does not match the current crossing frame"
	ErrInvalidSaltLength        = "invalid salt length"
	ErrTokenBucketNotFound      = "token bucket not found"
	ErrChannelBalanceV2NotFound = "channel balance v2 not found"
	ErrLockedNativeOverflow     = "locked native total overflows uint256"
	ErrInterfaceConversion      = "interface conversion failed"
)
