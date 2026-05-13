// Opens a mock-LC backed ZKGM channel pair and prints the ids. This is useful
// as setup for gnokey maketx call probes such as zkgm.SendRaw.
package main

import (
	e2e "gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/e2e"
)

func main() {
	e2e.RegisterMockLightClient(cross)
	pair := e2e.OpenE2EChannelPair(cross)

	println("source_channel", pair.Source.String())
	println("destination_channel", pair.Destination.String())
	println("client_id", pair.ClientId.String())
	println("connection_id", pair.ConnectionId.String())
}
