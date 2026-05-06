// PKGPATH: gno.land/r/aib/main
package main

import (
	"encoding/hex"
	"time"

	tmtesting "gno.land/p/aib/ibc/lightclient/tendermint/testing"
	"gno.land/p/aib/ibc/types"
	"gno.land/p/aib/ics23"
	"gno.land/r/aib/ibc/core"
)

// Acknowledgement success emits acknowledge_packet event.
func main() {
	var (
		chainID        = "chain-id-2"
		trustedHeight  = types.NewHeight(2, 2)
		clientState    = tmtesting.NewClientState(chainID, trustedHeight)
		apphash, _     = hex.DecodeString("a119217258843545bc79dd7df4c050c6c2a21b1de7c132dd065fd7463f743e2d")
		trustedValset  = tmtesting.GenValset()
		consensusState = tmtesting.GenConsensusState(time.Now(), apphash, trustedValset.Hash())
		counterpartyID = "07-tendermint-42"
	)
	clientID := core.CreateClient(cross, clientState, consensusState)
	core.RegisterCounterparty(cross, clientID, [][]byte{[]byte("iavlStoreKey"), []byte("prefix2")}, counterpartyID)

	appPortID := "app"
	core.RegisterApp(cross, appPortID, &noopApp{})

	sendPacket := types.MsgSendPacket{
		SourceClient:     clientID,
		TimeoutTimestamp: uint64(time.Now().Add(time.Hour).Unix()),
		Payloads: []types.Payload{{
			SourcePort:      appPortID,
			DestinationPort: "destinationPort",
			Encoding:        "application/json",
			Value:           []byte("{}"),
			Version:         "v1",
		}},
	}
	sequence := core.SendPacket(cross, sendPacket)

	specs := ics23.IavlSpec()
	proofAcked := []ics23.CommitmentProof{
		ics23.CommitmentProof_Exist{
			Exist: &ics23.ExistenceProof{
				Key:   []byte("\x70\x72\x65\x66\x69\x78\x32\x30\x37\x2d\x74\x65\x6e\x64\x65\x72\x6d\x69\x6e\x74\x2d\x34\x32\x03\x00\x00\x00\x00\x00\x00\x00\x01"),
				Value: []byte("\x21\x29\x3f\x61\xea\x42\x91\xdc\x31\x88\xaa\x8b\xe6\xde\x66\xeb\x0e\xe0\x5b\x10\x03\x25\xb0\x31\x3b\x25\x84\xf2\xc0\x96\x11\xaf"),
				Leaf: &ics23.LeafOp{
					Hash:         specs.LeafSpec.Hash,
					PrehashKey:   specs.LeafSpec.PrehashKey,
					PrehashValue: specs.LeafSpec.PrehashValue,
					Length:       specs.LeafSpec.Length,
					Prefix:       []byte("\x00\x02\x02"),
				},
				Path: []*ics23.InnerOp{
					{
						Hash:   specs.InnerSpec.Hash,
						Prefix: []byte("\x02\x04\x02\x20\x35\xf8\xea\x80\x53\x90\xe0\x84\x85\x4f\x39\x9b\x42\xcc\xde\xae\xa3\x3a\x1d\xed\xc1\x15\x63\x8a\xc4\x8d\x06\x00\x63\x7d\xba\x1f\x20"),
						Suffix: []byte(""),
					},
					{
						Hash:   specs.InnerSpec.Hash,
						Prefix: []byte("\x04\x08\x02\x20"),
						Suffix: []byte("\x20\x79\x8e\x2c\xaa\x96\xfd\xfb\xa3\x76\xdd\xeb\x47\x99\x99\x54\xd2\xf4\x7e\x65\x16\x22\x64\xb0\x53\x6a\xb5\xdf\xf7\xfc\x0a\x2e\x07"),
					},
					{
						Hash:   specs.InnerSpec.Hash,
						Prefix: []byte("\x06\x0c\x02\x20\x9a\xf3\x7d\xd5\x95\xa0\x19\x08\x03\xb5\xe0\x5a\xae\xf4\x2a\xe3\xfa\xd4\x99\xe4\xfb\xe3\x7f\x7c\xd3\x1c\xad\xff\x22\xa9\xee\x74\x20"),
						Suffix: []byte(""),
					},
				},
			},
		},
		ics23.CommitmentProof_Exist{
			Exist: &ics23.ExistenceProof{
				Key:   []byte("\x69\x61\x76\x6c\x53\x74\x6f\x72\x65\x4b\x65\x79"),
				Value: []byte("\x54\x67\x6b\x16\xcf\xa5\x41\x3e\x30\x2b\x0d\xff\x76\x7d\x1d\xa8\x11\x44\x0b\x38\x36\x08\xc7\xd8\xab\x6a\x1b\x36\x47\x82\x1f\x1d"),
				Leaf: &ics23.LeafOp{
					Hash:         specs.LeafSpec.Hash,
					PrehashKey:   specs.LeafSpec.PrehashKey,
					PrehashValue: specs.LeafSpec.PrehashValue,
					Length:       specs.LeafSpec.Length,
					Prefix:       []byte("\x00"),
				},
				Path: []*ics23.InnerOp{},
			},
		},
	}

	ackPacket := types.MsgAcknowledgement{
		Packet: types.Packet{
			Sequence:          sequence,
			SourceClient:      clientID,
			DestinationClient: counterpartyID,
			TimeoutTimestamp:  sendPacket.TimeoutTimestamp,
			Payloads:          sendPacket.Payloads,
		},
		Acknowledgement: types.Acknowledgement{
			AppAcknowledgements: [][]byte{[]byte(`{"response":{"result":"BQ=="}}`)},
		},
		ProofAcked:  proofAcked,
		ProofHeight: trustedHeight,
	}

	res := core.Acknowledgement(cross, ackPacket)
	println("res:", res)
}

type noopApp struct{}

func (a *noopApp) OnSendPacket(cur realm, sourceClient string, destinationClient string, sequence uint64, payload types.Payload) error {
	return nil
}

func (a *noopApp) OnRecvPacket(cur realm, sourceClient string, destinationClient string, sequence uint64, payload types.Payload) types.RecvPacketResult {
	return types.RecvPacketResult{Status: types.PacketStatus_Success}
}

func (a *noopApp) OnTimeoutPacket(cur realm, sourceClient string, destinationClient string, sequence uint64, payload types.Payload) error {
	return nil
}

func (a *noopApp) OnAcknowledgementPacket(cur realm, sourceClient string, destinationClient string, sequence uint64, acknowledgement []byte, payload types.Payload) error {
	return nil
}

// Output:
// res: (2 gno.land/p/aib/ibc/types.ResponseResultType)

// Events:
// [
//   {
//     "type": "create_client",
//     "attrs": [
//       {
//         "key": "client_id",
//         "value": "07-tendermint-1"
//       },
//       {
//         "key": "client_type",
//         "value": "07-tendermint"
//       },
//       {
//         "key": "consensus_heights",
//         "value": "2/2"
//       }
//     ],
//     "pkg_path": "gno.land/r/aib/ibc/core"
//   },
//   {
//     "type": "send_packet",
//     "attrs": [
//       {
//         "key": "packet_source_client",
//         "value": "07-tendermint-1"
//       },
//       {
//         "key": "packet_dest_client",
//         "value": "07-tendermint-42"
//       },
//       {
//         "key": "packet_sequence",
//         "value": "1"
//       },
//       {
//         "key": "packet_timeout_timestamp",
//         "value": "1234571490"
//       },
//       {
//         "key": "encoded_packet_hex",
//         "value": "0801120f30372d74656e6465726d696e742d311a1030372d74656e6465726d696e742d343220e2a1d8cc042a300a03617070120f64657374696e6174696f6e506f72741a02763122106170706c69636174696f6e2f6a736f6e2a027b7d"
//       }
//     ],
//     "pkg_path": "gno.land/r/aib/ibc/core"
//   },
//   {
//     "type": "acknowledge_packet",
//     "attrs": [
//       {
//         "key": "packet_source_client",
//         "value": "07-tendermint-1"
//       },
//       {
//         "key": "packet_dest_client",
//         "value": "07-tendermint-42"
//       },
//       {
//         "key": "packet_sequence",
//         "value": "1"
//       },
//       {
//         "key": "packet_timeout_timestamp",
//         "value": "1234571490"
//       },
//       {
//         "key": "encoded_packet_hex",
//         "value": "0801120f30372d74656e6465726d696e742d311a1030372d74656e6465726d696e742d343220e2a1d8cc042a300a03617070120f64657374696e6174696f6e506f72741a02763122106170706c69636174696f6e2f6a736f6e2a027b7d"
//       }
//     ],
//     "pkg_path": "gno.land/r/aib/ibc/core"
//   }
// ]
