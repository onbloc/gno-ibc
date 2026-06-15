// PKGPATH: gno.land/r/onbloc/ibc/apps/ucs03_zkgm/testing/realcometbls/scenarios
package scenarios

import (
	core "gno.land/r/onbloc/ibc/core"
	realadapter "gno.land/r/onbloc/ibc/lightclients/cometbls"
	realcometbls "gno.land/r/onbloc/ibc/apps/ucs03_zkgm/testing/realcometbls"
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
