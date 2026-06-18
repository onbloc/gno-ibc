package core

import "time"

// nowNanos returns the current block time in nanoseconds. Used for ICS-04
// packet timeout enforcement on the receive path.
func nowNanos() uint64 { return uint64(time.Now().UnixNano()) }
