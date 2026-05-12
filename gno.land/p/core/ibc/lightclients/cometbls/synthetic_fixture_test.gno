package cometbls

import (
	"testing"

	"gno.land/p/aib/ibc/types"
)

func TestSyntheticMembershipProofFixture(t *testing.T) {
	cases := []struct {
		name     string
		key      []byte
		value    []byte
		rootHex  string
		proofHex string
	}{
		{
			name:    "packet",
			key:     []byte("packet-key"),
			value:   []byte("packet-value"),
			rootHex: "13a5b650ff50759f50ef8f9591209557d51c4583ec4340862f769b0cf4644e0a",
			proofHex: "0a2b0a290a0a7061636b65742d6b6579120c7061636b65742d76616c75651a0d08011000180120012a03" +
				"0002020a360a340a036962631220dfc4876d278dc1a3b0a9c51d5b09b459f0b16fa9979c5abeddaab004" +
				"11afc7481a0b08011000180120012a0100",
		},
		{
			name:    "connection",
			key:     []byte("connection-state-key"),
			value:   []byte("connection-state-value"),
			rootHex: "d6ae73bed25818ea44b7ba5529f74fbee42140a30919ccfcc5b8694964fbd60b",
			proofHex: "0a3f0a3d0a14636f6e6e656374696f6e2d73746174652d6b65791216636f6e6e656374696f6e2d73" +
				"746174652d76616c75651a0d08011000180120012a030002020a360a340a036962631220c3d792b3969f81dd" +
				"123ebe65478b3f1cfb9fceaf31bbfeecb818946bbce021fb1a0b08011000180120012a0100",
		},
		{
			name:    "channel",
			key:     []byte("channel-state-key"),
			value:   []byte("channel-state-value"),
			rootHex: "b6b3f78c98373dc2def3dfb41014fa6c4ff9a0d9304d264ebcab73faa0260afb",
			proofHex: "0a390a370a116368616e6e656c2d73746174652d6b657912136368616e6e656c2d73746174652d76616c75" +
				"651a0d08011000180120012a030002020a360a340a03696263122064790b91a32f1d9d7c4aff72791ef938" +
				"d92ec9523b703c02558b459666854ddf1a0b08011000180120012a0100",
		},
	}

	for _, tc := range cases {
		proofs, err := DecodeProofs(mustHex(tc.proofHex))
		if err != nil {
			t.Fatalf("%s DecodeProofs: %v", tc.name, err)
		}

		cs := baseCS()
		client := newTestClient(cs, map[Height]ConsensusState{
			cs.LatestHeight: {
				Timestamp: testNow,
				Root:      MerkleRoot{Hash: mustHex(tc.rootHex)},
			},
		})
		path := types.MerklePath{KeyPath: [][]byte{[]byte("ibc"), tc.key}}
		if err := client.VerifyMembership(cs.LatestHeight, proofs, path, tc.value); err != nil {
			t.Fatalf("%s VerifyMembership: %v", tc.name, err)
		}
	}
}

func TestSyntheticNonMembershipProofFixture(t *testing.T) {
	key := []byte("packet-key-missing")
	rootHex := "13a5b650ff50759f50ef8f9591209557d51c4583ec4340862f769b0cf4644e0a"
	proofHex := "0a41123f0a127061636b65742d6b65792d6d697373696e6712290a0a7061636b65742d6b657912" +
		"0c7061636b65742d76616c75651a0d08011000180120012a030002020a360a340a036962631220df" +
		"c4876d278dc1a3b0a9c51d5b09b459f0b16fa9979c5abeddaab00411afc7481a0b080110001801" +
		"20012a0100"

	proofs, err := DecodeProofs(mustHex(proofHex))
	if err != nil {
		t.Fatalf("DecodeProofs: %v", err)
	}

	cs := baseCS()
	client := newTestClient(cs, map[Height]ConsensusState{
		cs.LatestHeight: {
			Timestamp: testNow,
			Root:      MerkleRoot{Hash: mustHex(rootHex)},
		},
	})
	path := types.MerklePath{KeyPath: [][]byte{[]byte("ibc"), key}}
	if err := client.VerifyNonMembership(cs.LatestHeight, proofs, path); err != nil {
		t.Fatalf("VerifyNonMembership: %v", err)
	}
}
