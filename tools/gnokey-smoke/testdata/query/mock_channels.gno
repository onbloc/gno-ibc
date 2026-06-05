package main

import (
	e2e "gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/e2e"
)

func main(cur realm) {
	e2e.RegisterMockLightClient(cross(cur))
	pair := e2e.OpenE2EChannelPair(cross(cur))
	println("mock_source", pair.Source.String())
	println("mock_destination", pair.Destination.String())
}
