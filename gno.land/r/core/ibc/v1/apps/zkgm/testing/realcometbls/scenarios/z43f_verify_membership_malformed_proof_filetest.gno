// PKGPATH: gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/realcometbls/scenarios
package scenarios

import (
	core "gno.land/r/core/ibc/v1/core"
	realadapter "gno.land/r/core/ibc/v1/lightclients/cometbls"
	realcometbls "gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/realcometbls"
)

func main(cur realm) {
	clientId := realcometbls.CreateRealCometBLSClient(cross(cur))
	realadapter.NewAdapter(cross(cur)).VerifyMembership(
		clientId,
		core.Height(realcometbls.DevnetHeight-1),
		[]byte{0x0a, 0xff},
		[]byte("key"),
		[]byte("value"),
	)
}

// Error:
// cometbls: invalid membership proof: proto: buffer underflow reading varint
