package realcometbls

import (
	"encoding/hex"

	cometblsp "gno.land/p/core/ibc/lightclients/cometbls"
)

const (
	DevnetChainID     = "union-devnet-1337"
	DevnetHeight      = int64(3405691582)
	DevnetTimeSeconds = int64(1732205251)
	DevnetTimeNanos   = int32(998131342)
)

var (
	devnetValidatorsHash = mustHex(
		"20DDFE7A0F75C65D876316091ECCD494A54A2BB324C872015F73E528D53CB9C4",
	)
	devnetAppHash = mustHex(
		"EE7E3E58F98AC95D63CE93B270981DF3EE54CA367F8D521ED1F444717595CD36",
	)
	devnetZKP = mustHex(
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
)

func ClientStateBytes(cur realm) []byte {
	return cometblsp.EncodeClientState(cometblsp.ClientState{
		ChainID:        DevnetChainID,
		TrustingPeriod: 100 * 365 * 24 * 3600 * 1_000_000_000,
		MaxClockDrift:  100 * 365 * 24 * 3600 * 1_000_000_000,
		LatestHeight:   cometblsp.Height(DevnetHeight - 1),
	})
}

func TrustedConsensusStateBytes(cur realm) []byte {
	bz, err := cometblsp.EncodeConsensusState(cometblsp.ConsensusState{
		Timestamp:          uint64(DevnetTimeSeconds-1000) * 1_000_000_000,
		NextValidatorsHash: cloneBytes(devnetValidatorsHash),
		Root: cometblsp.MerkleRoot{
			Hash: cloneBytes(devnetAppHash),
		},
	})
	if err != nil {
		panic(err)
	}
	return bz
}

func HeaderBytes(cur realm) []byte {
	return encodeHeader(devnetHeader(cloneBytes(devnetZKP)))
}

func TamperedHeaderBytes(cur realm) []byte {
	proof := cloneBytes(devnetZKP)
	proof[0] ^= 0xFF
	return encodeHeader(devnetHeader(proof))
}

func devnetHeader(proof []byte) cometblsp.Header {
	return cometblsp.Header{
		SignedHeader: cometblsp.LightHeader{
			Height:             DevnetHeight,
			TimeSeconds:        DevnetTimeSeconds,
			TimeNanos:          DevnetTimeNanos,
			ValidatorsHash:     cloneBytes(devnetValidatorsHash),
			NextValidatorsHash: cloneBytes(devnetValidatorsHash),
			AppHash:            cloneBytes(devnetAppHash),
		},
		TrustedHeight:      cometblsp.Height(DevnetHeight - 1),
		ZeroKnowledgeProof: proof,
	}
}

func encodeHeader(h cometblsp.Header) []byte {
	bz, err := cometblsp.EncodeHeader(h)
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

func cloneBytes(in []byte) []byte {
	out := make([]byte, len(in))
	copy(out, in)
	return out
}
