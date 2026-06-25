package impl

import (
	"gno.land/p/onbloc/ibc/union/types"
	core "gno.land/r/onbloc/ibc/union/core"
)

func assertIsRlmCurrent(_ int, rlm realm) {
	if !rlm.IsCurrent() {
		panic(errSpoofedRealm)
	}
}

func assertPacketDataSize(data []byte) {
	if core.PacketDataTooLarge(data) {
		panic(makeError(core.ErrPacketDataTooLarge))
	}
}

func assertPacketsDataSize(packets []types.Packet) {
	for _, packet := range packets {
		assertPacketDataSize(packet.Data)
	}
}
