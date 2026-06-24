package main

import (
	"gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/e2e"
)

func main(cur realm) {
	e2e.RegisterMockLightClient(cross(cur))
	pair := e2e.OpenE2EChannelPair(cross(cur))
	println("mock_source", pair.Source.String())
	println("mock_destination", pair.Destination.String())
}
