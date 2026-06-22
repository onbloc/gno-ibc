// PKGPATH: gno.land/p/onbloc/ibc/union/lightclient/cometbls/filetests/main
package main

import (
	"encoding/hex"

	"gno.land/p/onbloc/ibc/union/lightclient"
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

	printErr("malformed_proof", client.VerifyMembership(height, []byte("packet-key"), []byte{0x0a, 0xff}, []byte("packet-value")))
	printErr("wrong_key", client.VerifyMembership(height, []byte("wrong-key"), syntheticMembershipProof(), []byte("packet-value")))
	printErr("wrong_value", client.VerifyMembership(height, []byte("packet-key"), syntheticMembershipProof(), []byte("wrong-value")))
	printErr("wrong_root", newSyntheticClient(repeatByte(0xee, 32), longTrustingNanos, types.NewHeight(0)).VerifyMembership(
		height,
		[]byte("packet-key"),
		syntheticMembershipProof(),
		[]byte("packet-value"),
	))

	printStatus("frozen_status", newSyntheticClient(syntheticRoot(), longTrustingNanos, cometbls.FrozenHeight).Status())
	printStatus("expired_status", newSyntheticClientAt(syntheticRoot(), 1, types.NewHeight(0), 1).Status())

	printVerifyHeaderErr("malformed_header", client, []byte{0x01, 0x02})
	printVerifyHeaderErr("bad_header", client, tamperedHeaderBytes())
}

func printErr(label string, err error) {
	if err == nil {
		println(label, "ok")
		return
	}
	println(label, err.Error())
}

func printStatus(label string, status lightclient.Status) {
	println(label, string(status))
}

func printVerifyHeaderErr(label string, client *cometbls.CometblsLightClient, header []byte) {
	_, err := client.VerifyHeader(address("g1caller"), header, address("g1relayer"))
	printErr(label, err)
}

func newSyntheticClient(root []byte, trustingPeriod uint64, frozenHeight types.Height) *cometbls.CometblsLightClient {
	return newSyntheticClientAt(root, trustingPeriod, frozenHeight, uint64(1732204251)*1_000_000_000)
}

func newSyntheticClientAt(root []byte, trustingPeriod uint64, frozenHeight types.Height, timestamp uint64) *cometbls.CometblsLightClient {
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
		timestamp,
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

func tamperedHeaderBytes() []byte {
	proof := mustHex(
		"03CF56142A1E03D2445A82100FEAF70C1CD95A731ED85792AFFF5792EC0BDD21" +
			"08991BB56F9043A269F88903DE616A9AB99A3C5AB778E566744B060456C5616C" +
			"06BCE7F1930421768C2CBD79F88D08EC3A52D7C9A867064E973064385E9C945E" +
			"02951190DD7CE1662546733DD540188C96E608CA750FEF36B39E2577833634C7" +
			"0AE6F1A6D00DC6C21446AAF285EF35D944E8782B131300574F9A889C7E708A23" +
			"25E9A78013BBE869D38B19C602DAF69644C77D177E99ED76398BCEE13C61FDBF" +
			"2E178A5BA028A36033E54D1D9A0071E82E04079A5305347EBAC6D66F6EBFA48B" +
			"1DA1BF9DC5A51EFA292E1DC7B85D26F18422EB386C48CA75434039764448BB96" +
			"268DDC2CF683DDCA4BD83DF21C5631CF784375EEBE77EABC2DE77886BF1D4839" +
			"2C9C52E063B4A7131EAB9ABBA12A9F26888BC37366D41AC7D4BAC0BF6755ACB0" +
			"09BF9F36F380B6D0EEAABF066503A1B6E01DCC965D968D7694E01B1755E6BDD2" +
			"1C7A80B41682748F9B7151714BE34AA79AAD48BBB2A84525F6CDF812658C6E4F",
	)
	proof[0] ^= 0xff
	trustedHeight := types.NewHeight(devnetHeight - 1)
	header := cometbls.NewHeader(
		cometbls.NewLightHeader(
			int64(devnetHeight),
			1732205251,
			998131342,
			mustHex("20ddfe7a0f75c65d876316091eccd494a54a2bb324c872015f73e528d53cb9c4"),
			mustHex("20ddfe7a0f75c65d876316091eccd494a54a2bb324c872015f73e528d53cb9c4"),
			mustHex("ee7e3e58f98ac95d63ce93b270981df3ee54ca367f8d521ed1f444717595cd36"),
		),
		&trustedHeight,
		proof,
	)
	bz, err := cometbls.EncodeHeader(header)
	if err != nil {
		panic(err)
	}
	return bz
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

func repeatByte(b byte, n int) []byte {
	out := make([]byte, n)
	for i := 0; i < n; i++ {
		out[i] = b
	}
	return out
}

// Output:
// malformed_proof invalid proof, failed to decode proof: buffer underflow while reading varint
// wrong_key invalid proof, failed to verify membership proof at index 0: provided key doesn't match proof
// wrong_value invalid proof, failed to verify membership proof at index 0: provided value doesn't match proof
// wrong_root invalid proof, proof did not commit to expected root: eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee, got: 4b65474532ba60c0ebbf93f54072915c2df0051ffd722282eca58b40ba86cf88. Please ensure proof was submitted with correct proofHeight and to the correct chain.
// frozen_status Frozen
// expired_status Expired
// malformed_header invalid header, failed to decode header: cometbls: abi: invalid data
// bad_header invalid header, zero-knowledge proof verification failed: cometblszk: invalid proof
