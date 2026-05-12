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
			rootHex: "4d52c3c46fce6c9d7cd187c0cbf6a7dd6e8f0d89661d98b5b9e2161d8a965323",
			proofHex: "0a560a540a0a7061636b65742d6b6579120c7061636b65742d76616c75651a0d08011000180120012a03" +
				"00020222290801122504060220d1e824347279953135d11eb8eca353e5e22dcf0b08b408dc170c133c0fc00f" +
				"49200a360a340a036962631220755595e19553fed6b6654dc0ea6c44fae960c5c242cba6b336412fb2b45a02" +
				"eb1a0b08011000180120012a0100",
		},
		{
			name:    "connection",
			key:     []byte("connection-state-key"),
			value:   []byte("connection-state-value"),
			rootHex: "4d52c3c46fce6c9d7cd187c0cbf6a7dd6e8f0d89661d98b5b9e2161d8a965323",
			proofHex: "0a98010a95010a14636f6e6e656374696f6e2d73746174652d6b65791216636f6e6e656374696f6e2d73" +
				"746174652d76616c75651a0d08011000180120012a030002022229080112250204022064790b91a32f1d9d7" +
				"c4aff72791ef938d92ec9523b703c02558b459666854ddf20222b08011204040602201a2120dfc4876d278d" +
				"c1a3b0a9c51d5b09b459f0b16fa9979c5abeddaab00411afc7480a360a340a036962631220755595e19553" +
				"fed6b6654dc0ea6c44fae960c5c242cba6b336412fb2b45a02eb1a0b08011000180120012a0100",
		},
		{
			name:    "channel",
			key:     []byte("channel-state-key"),
			value:   []byte("channel-state-value"),
			rootHex: "4d52c3c46fce6c9d7cd187c0cbf6a7dd6e8f0d89661d98b5b9e2161d8a965323",
			proofHex: "0a94010a91010a116368616e6e656c2d73746174652d6b657912136368616e6e656c2d73746174652d7661" +
				"6c75651a0d08011000180120012a03000202222b08011204020402201a2120c3d792b3969f81dd123ebe65" +
				"478b3f1cfb9fceaf31bbfeecb818946bbce021fb222b08011204040602201a2120dfc4876d278dc1a3b0" +
				"a9c51d5b09b459f0b16fa9979c5abeddaab00411afc7480a360a340a036962631220755595e19553fed6" +
				"b6654dc0ea6c44fae960c5c242cba6b336412fb2b45a02eb1a0b08011000180120012a0100",
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
	rootHex := "4d52c3c46fce6c9d7cd187c0cbf6a7dd6e8f0d89661d98b5b9e2161d8a965323"
	proofHex := "0a6c126a0a127061636b65742d6b65792d6d697373696e6712540a0a7061636b65742d6b657912" +
		"0c7061636b65742d76616c75651a0d08011000180120012a0300020222290801122504060220d1" +
		"e824347279953135d11eb8eca353e5e22dcf0b08b408dc170c133c0fc00f49200a360a340a03" +
		"6962631220755595e19553fed6b6654dc0ea6c44fae960c5c242cba6b336412fb2b45a02eb1a" +
		"0b08011000180120012a0100"

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
