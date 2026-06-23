package zkgm

// ErrSpoofedRealm guards non-crossing (_ int, rlm realm, ...) entrypoints: the
// passed rlm must be the current crossing frame, not a forged or stale token
// replayed by a caller.
const ErrSpoofedRealm = "rlm does not match the current crossing frame"
