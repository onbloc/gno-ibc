package main

import realcometbls "gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/realcometbls"

func main() {
	clientId := realcometbls.CreateRealCometBLSClient(cross)
	realcometbls.UpdateRealCometBLSClientWithTamperedHeader(cross, clientId)
}

// Error:
// cometbls: cometblszk: invalid proof
