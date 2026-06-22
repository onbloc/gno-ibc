// PKGPATH: gno.land/p/onbloc/ibc/union/lightclient/cometbls/filetests/main
package main

import (
	"encoding/hex"

	cometbls "gno.land/p/onbloc/ibc/union/lightclient/cometbls"
	"gno.land/p/onbloc/ibc/union/types"
)

const (
	devnetHeight      = uint64(3405691582)
	devnetChainID     = "union-devnet-1337"
	longTrustingNanos = uint64(100 * 365 * 24 * 3600 * 1_000_000_000)
)

func main() {
	client := newSyntheticClient(syntheticRoot(), longTrustingNanos, types.NewHeight(0))
	height := devnetHeight - 1

	printErr("membership", client.VerifyMembership(
		height,
		[]byte("packet-key"),
		syntheticMembershipProof(),
		[]byte("packet-value"),
	))
	printErr("non_membership", client.VerifyNonMembership(
		height,
		[]byte("packet-key-missing"),
		syntheticNonMembershipProof(),
	))
}

func printErr(label string, err error) {
	if err == nil {
		println(label, "ok")
		return
	}
	println(label, err.Error())
}

func newSyntheticClient(root []byte, trustingPeriod uint64, frozenHeight types.Height) *cometbls.CometblsLightClient {
	clientState := cometbls.NewClientState(
		devnetChainID,
		trustingPeriod,
		longTrustingNanos+1,
		longTrustingNanos,
		frozenHeight,
		types.NewHeight(devnetHeight-1),
		mustH256("0cf2ffe8f45a20514018173d3007644817a9767dc0fbdb246696fd9c261ce3bc"),
	)
	consensusState := cometbls.NewConsensusState(
		uint64(1732204251)*1_000_000_000,
		cometbls.MerkleRoot{Hash: root},
		mustHex("20ddfe7a0f75c65d876316091eccd494a54a2bb324c872015f73e528d53cb9c4"),
	)
	client, err := cometbls.NewCometblsLightClient(clientState, consensusState)
	if err != nil {
		panic(err)
	}
	return client
}

func syntheticRoot() []byte {
	return mustHex("4b65474532ba60c0ebbf93f54072915c2df0051ffd722282eca58b40ba86cf88")
}

func syntheticMembershipProof() []byte {
	return mustHex(
		"0a780a760a2c030cf2ffe8f45a20514018173d3007644817a9767dc0fbdb246696fd9c261ce3bc00706163" +
			"6b65742d6b6579120c7061636b65742d76616c75651a0d08011000180120012a030002022229080112250406" +
			"022094f02598e6ac1ddca02733c633b1e372b11ef1e2b05a18c4eaf7a15cc98a17f9200a370a350a047761736d" +
			"12200aea765e9bcd8f9f4bdce60cdc2720970b8a9c0b5deff85347e968de1d1d9b591a0b08011000180120012a0100",
	)
}

func syntheticNonMembershipProof() []byte {
	return mustHex(
		"0a8f01128c010a127061636b65742d6b65792d6d697373696e6712760a2c030cf2ffe8f45a20514018173d" +
			"3007644817a9767dc0fbdb246696fd9c261ce3bc007061636b65742d6b6579120c7061636b65742d76616c75" +
			"651a0d08011000180120012a030002022229080112250406022094f02598e6ac1ddca02733c633b1e372b11e" +
			"f1e2b05a18c4eaf7a15cc98a17f9200a370a350a047761736d12200aea765e9bcd8f9f4bdce60cdc2720970b8a" +
			"9c0b5deff85347e968de1d1d9b591a0b08011000180120012a0100",
	)
}

func mustHex(s string) []byte {
	bz, err := hex.DecodeString(s)
	if err != nil {
		panic(err)
	}
	return bz
}

func mustH256(s string) cometbls.H256 {
	bz := mustHex(s)
	if len(bz) != 32 {
		panic("H256 must be 32 bytes")
	}
	var out cometbls.H256
	copy(out[:], bz)
	return out
}

// Output:
// membership ok
// non_membership ok
