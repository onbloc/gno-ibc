package main

import realcometbls "gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/realcometbls"

func main() {
	clientId := realcometbls.CreateRealCometBLSClient(cross)
	height := realcometbls.UpdateRealCometBLSClient(cross, clientId)

	println("client_id", clientId.String())
	println("updated_height", height.String())
}

// Output:
// client_id 1
// updated_height 3405691582
