// PKGPATH: gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/realcometbls/scenarios
package scenarios

import (
	realcometbls "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/realcometbls"
	impl "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
)

func main(cur realm) {
	impl.Register(cross(cur))
	pair := realcometbls.OpenZ35CometBLSChannel(cross(cur))

	println("client", pair.ClientId.String())
	println("connection", pair.ConnectionId.String())
	println("source", pair.Source.String())
	println("destination", pair.Destination.String())
}

// Output:
// client 1
// connection 1
// source 2
// destination 1
