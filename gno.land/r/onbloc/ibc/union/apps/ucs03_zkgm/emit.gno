package zkgm

import (
	"gno.land/p/onbloc/ibc/union/types"
)

func EmitRecvError(_ int, rlm realm, sourceChannel types.ChannelId, destinationChannel types.ChannelId, reason string) {
	assertIsRlmCurrent(0, rlm)
	assertIsProxyRealm(0, rlm)
	emitRecvError(sourceChannel, destinationChannel, reason)
}
