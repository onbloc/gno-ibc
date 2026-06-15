// PKGPATH: gno.land/r/onbloc/ibc/apps/ucs03_zkgm/testing/realcometbls/scenarios
package scenarios

import (
	realcometbls "gno.land/r/onbloc/ibc/apps/ucs03_zkgm/testing/realcometbls"
	_ "gno.land/r/onbloc/ibc/apps/ucs03_zkgm/v1/loader"
)

func main(cur realm) {
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
