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
		{
			name:    "z35_connection_try",
			key:     mustHex("05f3c8eef62e74b10b7ee910fcc73c8358000f692d9ce2341a989e008e45b35d"),
			value:   mustHex("ff4fb67348c16e70c898c7cf43c460a684bc900d2b41e5a24ef6dcb294586034"),
			rootHex: "32de831f9c1a2d12abdc7448f045982c348ff7c23d9b8c7313c855c5b1f81edd",
			proofHex: "0ab0010aad010a2005f3c8eef62e74b10b7ee910fcc73c8358000f692d9ce2341a989e008e45" +
				"b35d1220ff4fb67348c16e70c898c7cf43c460a684bc900d2b41e5a24ef6dcb2945860341a0d" +
				"08011000180120012a03000202222b08011204020402201a212005f5c45fdd378e7f94009469a4d" +
				"569164f400251f70d2de446a023d527b0e75b222b08011204040602201a21201c088875fa1d31" +
				"2c11a5906d629222fb38eb4d95c71a0c2c7899672746f529150a360a340a036962631220a6c1e7" +
				"0fa2cceb831692a8607087e2f0fecc025e2fee771bf13ae95902ad1f831a0b08011000180120012a0100",
		},
		{
			name:    "z35_channel_try",
			key:     mustHex("88601476d11616a71c5be67555bd1dff4b1cbf21533d2669b768b61518cfe1c3"),
			value:   mustHex("fa3c11d224a164cd0beca2b6756128dc1531714a75813e9c2b5840bd8f2a8347"),
			rootHex: "32de831f9c1a2d12abdc7448f045982c348ff7c23d9b8c7313c855c5b1f81edd",
			proofHex: "0a80010a7e0a2088601476d11616a71c5be67555bd1dff4b1cbf21533d2669b768b61518cfe1c3" +
				"1220fa3c11d224a164cd0beca2b6756128dc1531714a75813e9c2b5840bd8f2a83471a0d080110" +
				"00180120012a030002022229080112250406022077c53ef3699e25b3dfb6a8b666f3e28020fb6207" +
				"bef226187ced9052524cc749200a360a340a036962631220a6c1e70fa2cceb831692a8607087e2f0" +
				"fecc025e2fee771bf13ae95902ad1f831a0b08011000180120012a0100",
		},
		{
			name:    "z35_packet_commitment",
			key:     mustHex("6cdd701570bc5e4ca75bc46a6499076fcd9d3485329063a1cf23cf6ee66a5d10"),
			value:   mustHex("0100000000000000000000000000000000000000000000000000000000000000"),
			rootHex: "32de831f9c1a2d12abdc7448f045982c348ff7c23d9b8c7313c855c5b1f81edd",
			proofHex: "0aae010aab010a206cdd701570bc5e4ca75bc46a6499076fcd9d3485329063a1cf23cf6ee66a5d10" +
				"122001000000000000000000000000000000000000000000000000000000000000001a0d080110" +
				"00180120012a03000202222908011225020402208cb10ed5327260edb18c98511ad911082d8a530" +
				"ba825451f7d79389195ecf96820222b08011204040602201a21201c088875fa1d312c11a5906d62" +
				"9222fb38eb4d95c71a0c2c7899672746f529150a360a340a036962631220a6c1e70fa2cceb831692" +
				"a8607087e2f0fecc025e2fee771bf13ae95902ad1f831a0b08011000180120012a0100",
		},
		{
			name:    "z36_ack_membership",
			key:     mustHex("7cdf87cee2bf28fffdd8dd98af1ed5bd99585afb5b6e537d718f1f9391b44067"),
			value:   mustHex("41502841361a25f62632a8138da2f5da1948539832b0fc2bfb733cc7b081836e"),
			rootHex: "a1be834affb97f92fa64a9fb234a7b9692adeae6a984de2f6afce4efd6b080b2",
			proofHex: "0a80010a7e0a207cdf87cee2bf28fffdd8dd98af1ed5bd99585afb5b6e537d718f1f9391b44067" +
				"122041502841361a25f62632a8138da2f5da1948539832b0fc2bfb733cc7b081836e1a0d080110" +
				"00180120012a0300020222290801122502040220673b9cd2b12cf905618f6b5f169960026fbfd2e1" +
				"620582d85278f42c8f3dbabb200a360a340a03696263122073f8956e449da09927af05f41734ef" +
				"2691cd5a6b7b64b9847be76a1fe10c49711a0b08011000180120012a0100",
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
	cases := []struct {
		name     string
		key      []byte
		rootHex  string
		proofHex string
	}{
		{
			name:    "packet",
			key:     []byte("packet-key-missing"),
			rootHex: "4d52c3c46fce6c9d7cd187c0cbf6a7dd6e8f0d89661d98b5b9e2161d8a965323",
			proofHex: "0a6c126a0a127061636b65742d6b65792d6d697373696e6712540a0a7061636b65742d6b657912" +
				"0c7061636b65742d76616c75651a0d08011000180120012a0300020222290801122504060220d1" +
				"e824347279953135d11eb8eca353e5e22dcf0b08b408dc170c133c0fc00f49200a360a340a03" +
				"6962631220755595e19553fed6b6654dc0ea6c44fae960c5c242cba6b336412fb2b45a02eb1a" +
				"0b08011000180120012a0100",
		},
		{
			name:    "z37_receipt",
			key:     mustHex("aaa7bd6e1524998c867fc9248d3940e6873a82884f0754f79fd7bec370f222b7"),
			rootHex: "a1be834affb97f92fa64a9fb234a7b9692adeae6a984de2f6afce4efd6b080b2",
			proofHex: "0aa50112a2010a20aaa7bd6e1524998c867fc9248d3940e6873a82884f0754f79fd7bec370f222" +
				"b7127e0a207cdf87cee2bf28fffdd8dd98af1ed5bd99585afb5b6e537d718f1f9391b440671220" +
				"41502841361a25f62632a8138da2f5da1948539832b0fc2bfb733cc7b081836e1a0d0801100018" +
				"0120012a0300020222290801122502040220673b9cd2b12cf905618f6b5f169960026fbfd2e162" +
				"0582d85278f42c8f3dbabb200a360a340a03696263122073f8956e449da09927af05f41734ef26" +
				"91cd5a6b7b64b9847be76a1fe10c49711a0b08011000180120012a0100",
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
		if err := client.VerifyNonMembership(cs.LatestHeight, proofs, path); err != nil {
			t.Fatalf("%s VerifyNonMembership: %v", tc.name, err)
		}
	}
}
