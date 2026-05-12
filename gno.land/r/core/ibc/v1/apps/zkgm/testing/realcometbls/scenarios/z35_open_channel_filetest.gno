package main

import (
	realcometbls "gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/realcometbls"
	_ "gno.land/r/gnoswap/ibc/v1/apps/zkgm/v0/loader"
)

func main() {
	pair := realcometbls.OpenZ35CometBLSChannel(cross)

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
