package zkgm

import (
	"testing"

	types "gno.land/p/onbloc/ibc/union/types"
)

func TestEmitRecvErrorAllowsProxyRealmCaller(cur realm, t *testing.T) {
	EmitRecvError(0, cur, types.ChannelId(1), types.ChannelId(2), "error")
}
