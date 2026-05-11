package main

import (
	realadapter "gno.land/r/core/ibc/v1/lightclients/cometbls"
	realcometbls "gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/realcometbls"
)

func main() {
	clientId := realcometbls.CreateRealCometBLSClient(cross)
	height := realcometbls.UpdateRealCometBLSClient(cross, clientId)
	latestHeight := realadapter.Adapter{}.GetLatestHeight(clientId)
	timestamp := realadapter.Adapter{}.GetTimestamp(clientId, height)
	status := realadapter.Adapter{}.GetStatus(clientId)

	println("client_id", clientId.String())
	println("updated_height", height.String())
	println("latest_height", latestHeight.String())
	println("timestamp", timestamp.String())
	println("status", uint8(status))
}

// Output:
// client_id 1
// updated_height 3405691582
// latest_height 3405691582
// timestamp 1732205251998131342
// status 1
