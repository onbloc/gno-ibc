package impl

import (
	core "gno.land/r/onbloc/ibc/union/core"
)

func assertIsRlmCurrent(_ int, rlm realm) {
	if !rlm.IsCurrent() {
		panic(errSpoofedRealm)
	}
}

func assertPacketDataSize(data []byte) {
	if core.PacketDataTooLarge(data) {
		panic(makeError(core.ErrPacketCombinedDataTooLarge))
	}
}
