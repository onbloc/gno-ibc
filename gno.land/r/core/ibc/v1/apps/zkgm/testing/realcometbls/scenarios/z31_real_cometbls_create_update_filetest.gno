// PKGPATH: gno.land/r/onbloc/ibc/v1/apps/zkgm/testing/realcometbls/scenarios
package scenarios

import (
	realadapter "gno.land/r/core/ibc/v1/lightclients/cometbls"
	realcometbls "gno.land/r/onbloc/ibc/v1/apps/zkgm/testing/realcometbls"
)

func main(cur realm) {
	clientId := realcometbls.CreateRealCometBLSClient(cross(cur))
	height := realcometbls.UpdateRealCometBLSClient(cross(cur), clientId)
	latestHeight := realadapter.NewAdapter(cross(cur)).GetLatestHeight(clientId)
	timestamp := realadapter.NewAdapter(cross(cur)).GetTimestamp(clientId, height)
	status := realadapter.NewAdapter(cross(cur)).GetStatus(clientId)

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
