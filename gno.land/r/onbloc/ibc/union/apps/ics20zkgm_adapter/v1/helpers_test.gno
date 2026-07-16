package ics20zkgm_adapter

import (
	"gno.land/p/nt/testutils/v0"
	types "gno.land/p/onbloc/ibc/union/types"
	"gno.land/r/aib/ibc/apps/transfer"
	adapter "gno.land/r/onbloc/ibc/union/apps/ics20zkgm_adapter"
)

// helpers_test.gno holds test fixtures shared across the per-file test suites,
// mirroring apps/ucs03_zkgm/v1/helpers_test.gno's layout.

// testStore is the in-memory IStore mock injected into the impl under test.
// The proxy keeps its real Store private (no exported getter), so unit tests
// inject this test-realm-owned mock instead (see mockstore_test.gno). Each
// test resets it (testStore = newMockStore()) so state doesn't leak across
// tests sharing the same test binary.
var testStore = newMockStore()

// newTestImpl builds a v1 impl bound to the test-owned store, the way the
// proxy injects its singleton at UpdateImpl time.
func newTestImpl() *Impl {
	return NewImpl(testStore)
}

func testAddress(name string) address {
	return testutils.TestAddress(name)
}

func testDenomConfig() adapter.DenomConfig {
	return adapter.NewDenomConfig(types.ChannelId(1), []byte("quote-token-placeholder"), []byte("metadata-placeholder"))
}

const (
	fwdSourceClient = "07-tendermint-0"
	fwdDestClient   = "07-tendermint-1"
	fwdForwardMemo  = `{"forward":{"receiver":"0xabc123"}}`
)

// testMintDenom is the Denom OnRecvPacket would construct for a mint-path
// recv of baseDenom: a single destination-port/client hop, no prior trace.
func testMintDenom(baseDenom string) transfer.Denom {
	return transfer.NewDenom(baseDenom, transfer.NewHop(transfer.PortID, fwdDestClient))
}
