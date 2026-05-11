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
	syntheticMembershipRoot = mustHex(
		"13a5b650ff50759f50ef8f9591209557d51c4583ec4340862f769b0cf4644e0a",
	)
	syntheticMembershipProof = mustHex(
		"0a2b0a290a0a7061636b65742d6b6579120c7061636b65742d76616c75651a0d08011000180120012a03" +
			"0002020a360a340a036962631220dfc4876d278dc1a3b0a9c51d5b09b459f0b16fa9979c5abeddaab004" +
			"11afc7481a0b08011000180120012a0100",
	)
	syntheticMembershipWrongSubrootProof = mustHex(
		"0a2b0a290a0a7061636b65742d6b6579120c7061636b65742d76616c75651a0d08011000180120012a03" +
			"0002020a360a340a036962631220dec4876d278dc1a3b0a9c51d5b09b459f0b16fa9979c5abeddaab004" +
			"11afc7481a0b08011000180120012a0100",
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
	return consensusStateBytes(devnetAppHash)
}

func SyntheticConsensusStateBytes(cur realm) []byte {
	return consensusStateBytes(syntheticMembershipRoot)
}

func consensusStateBytes(root []byte) []byte {
	bz, err := cometblsp.EncodeConsensusState(cometblsp.ConsensusState{
		Timestamp:          uint64(DevnetTimeSeconds-1000) * 1_000_000_000,
		NextValidatorsHash: cloneBytes(devnetValidatorsHash),
		Root: cometblsp.MerkleRoot{
			Hash: cloneBytes(root),
		},
	})
	if err != nil {
		panic(err)
	}
	return bz
}

func SyntheticMembershipKey(cur realm) []byte {
	return []byte("packet-key")
}

func SyntheticMembershipValue(cur realm) []byte {
	return []byte("packet-value")
}

func SyntheticMembershipProof(cur realm) []byte {
	return cloneBytes(syntheticMembershipProof)
}

func SyntheticMembershipWrongSubrootProof(cur realm) []byte {
	return cloneBytes(syntheticMembershipWrongSubrootProof)
}

func HeaderBytes(cur realm) []byte {
	return encodeHeader(devnetHeader(cloneBytes(devnetZKP)))
}

func TamperedHeaderBytes(cur realm) []byte {
	proof := cloneBytes(devnetZKP)
	proof[0] ^= 0xFF
	return encodeHeader(devnetHeader(proof))
}

func TwoExistenceProofStubs(cur realm) []byte {
	return encodeMerkleProof(
		encodeCommitmentExist(encodeExistenceProof([]byte("leaf-key"), []byte("leaf-value"))),
		encodeCommitmentExist(encodeExistenceProof([]byte("ibc"), []byte("subroot"))),
	)
}

func OneExistenceProofStub(cur realm) []byte {
	return encodeMerkleProof(
		encodeCommitmentExist(encodeExistenceProof([]byte("leaf-key"), []byte("leaf-value"))),
	)
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

func pbVarint(v uint64) []byte {
	var out []byte
	for v >= 0x80 {
		out = append(out, byte(v)|0x80)
		v >>= 7
	}
	return append(out, byte(v))
}

func pbTag(fieldNum, wireType int) []byte {
	return pbVarint(uint64(fieldNum<<3 | wireType))
}

func pbBytesField(fieldNum int, data []byte) []byte {
	out := pbTag(fieldNum, 2)
	out = append(out, pbVarint(uint64(len(data)))...)
	return append(out, data...)
}

func encodeExistenceProof(key, value []byte) []byte {
	var out []byte
	if len(key) > 0 {
		out = append(out, pbBytesField(1, key)...)
	}
	if len(value) > 0 {
		out = append(out, pbBytesField(2, value)...)
	}
	return out
}

func encodeCommitmentExist(epBytes []byte) []byte {
	return pbBytesField(1, epBytes)
}

func encodeMerkleProof(proofs ...[]byte) []byte {
	var out []byte
	for _, proof := range proofs {
		out = append(out, pbBytesField(1, proof)...)
	}
	return out
}
