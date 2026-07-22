// PKGPATH: gno.land/r/aib/main
package main

// atomone_recv_forward_via_zkgm_filetest proves the AtomOne -> Gno ICS20 ->
// Gno ZKGM leg of issue #248's single-sign design: an AtomOne recv carrying a
// PFM-style forward memo mints the voucher to transfer's own realm address
// instead of Receiver, and forwards it onward via zkgm.SendWithCallback,
// deferring this packet's own ack (PacketStatus_Async).
//
// Scope: recv -> forward send only. The ZKGM leg's ack/timeout coming back
// (OnZkgmSendResult resolving the deferred ack) is not exercised here.

import (
	"encoding/hex"
	"testing"
	"time"

	tmtesting "gno.land/p/aib/ibc/lightclient/tendermint/testing"
	"gno.land/p/aib/ibc/types"
	"gno.land/p/aib/ics23"
	"gno.land/p/nt/ufmt/v0"
	unionlightclient "gno.land/p/onbloc/ibc/union/lightclient"
	unionTypes "gno.land/p/onbloc/ibc/union/types"
	"gno.land/r/aib/ibc/apps/transfer"
	"gno.land/r/aib/ibc/core"

	"gno.land/r/onbloc/ibc/union/access"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	_ "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	unioncore "gno.land/r/onbloc/ibc/union/core"
	_ "gno.land/r/onbloc/ibc/union/core/v1"
)

const (
	coreImplPath   = "gno.land/r/onbloc/ibc/union/core/v1"
	zkgmImplPath   = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	adminAddr      = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
	mockClientType = unionTypes.ClientType("scenario-mock-lc")

	// Fixed rather than derived from time.Now(): the ProofCommitment below is
	// a proof over a packet JSON that embeds this exact value (see the
	// gen-proof command in the NOTE comment), so it can't drift.
	timeoutTimestamp = uint64(1234571490)
)

// --- permissive mock light client (accepts any proof) ---

type mockLightClient struct{}

func (m *mockLightClient) VerifyMembership(uint64, []byte, []byte, []byte) error { return nil }
func (m *mockLightClient) VerifyNonMembership(uint64, []byte, []byte) error      { return nil }
func (m *mockLightClient) GetTimestamp() unionTypes.Timestamp                    { return unionTypes.Timestamp(1) }
func (m *mockLightClient) GetTimestampAtHeight(uint64) (unionTypes.Timestamp, error) {
	return unionTypes.Timestamp(1), nil
}
func (m *mockLightClient) GetLatestHeight() uint64         { return 1 }
func (m *mockLightClient) GetCounterpartyChainID() string  { return "mock-chain" }
func (m *mockLightClient) Status() unionlightclient.Status { return unionlightclient.Active }

func (m *mockLightClient) VerifyHeader(_ address, header []byte, _ address) (unionTypes.StateUpdate, error) {
	return unionTypes.StateUpdate{Height: 1, ClientStateBytes: header, ConsensusStateBytes: header}, nil
}
func (m *mockLightClient) VerifyCreation(address, address) (unionTypes.ClientCreationResult, error) {
	return unionTypes.ClientCreationResult{}, nil
}
func (m *mockLightClient) Misbehaviour(address, []byte, address) ([]byte, error) {
	return nil, errMisbehaviourUnsupported
}

type mockError string

func (e mockError) Error() string { return string(e) }

var errMisbehaviourUnsupported = mockError("mock: misbehaviour unsupported")

func main(cur realm) {
	// --- Union/ZKGM side bootstrap (mock light client, no proof needed for send) ---
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	unioncore.UpdateImpl(cross(cur), coreImplPath)
	zkgm.UpdateImpl(cross(cur), zkgmImplPath)
	zkgm.SetRateLimitDisabled(cross(cur), true)
	zkgm.RegisterCoreApp(cross(cur))
	access.GrantRole(cross(cur), access.RelayerRole, adminAddr)
	unioncore.RegisterClient(cross(cur), mockClientType, func(_, _ []byte) (unionlightclient.Interface, error) {
		return &mockLightClient{}, nil
	})

	unioncore.CreateClient(cross(cur), unioncore.NewMsgCreateClient(mockClientType, nil, nil))
	unionClientId := unionTypes.ClientId(1)

	unioncore.ConnectionOpenInit(cross(cur), unioncore.NewMsgConnectionOpenInit(unionClientId, unionTypes.ClientId(99)))
	unionConnectionId := unionTypes.ConnectionId(1)
	unioncore.ConnectionOpenAck(cross(cur), unioncore.NewMsgConnectionOpenAck(unionConnectionId, unionTypes.ConnectionId(77), nil, 1))

	unionPortId := []byte(zkgm.ProxyPkgPath())
	unioncore.ChannelOpenInit(cross(cur), unioncore.NewMsgChannelOpenInit(unionPortId, unionPortId, unionConnectionId, zkgm.Version, "g1relayer"))
	unionChannelId := unionTypes.ChannelId(1)
	unioncore.ChannelOpenAck(cross(cur), unioncore.NewMsgChannelOpenAck(unionChannelId, zkgm.Version, unionTypes.ChannelId(2), nil, 1, "g1relayer"))

	println("[INFO] union channel opened:", unionChannelId.String())

	// transfer registers itself as ZKGM's send-result notification target.
	transfer.RegisterZkgmSendCallback(cross(cur))

	// --- AtomOne side: real tendermint client (no packet proof needed for CreateClient) ---
	var (
		chainID        = "chainA-2"
		trustedHeight  = types.NewHeight(2, 2)
		clientState    = tmtesting.NewClientState(chainID, trustedHeight)
		apphash, _     = hex.DecodeString("5667793a4a4fa4334ecbaa8f4c95e85d7214e137e421d99ad336cde4f33ddf48")
		trustedValset  = tmtesting.GenValset()
		consensusState = tmtesting.GenConsensusState(time.Now(), apphash, trustedValset.Hash())
		counterpartyID = "07-tendermint-42"
	)
	clientID := core.CreateClient(cross(cur), clientState, consensusState)
	core.RegisterCounterparty(cross(cur), clientID, [][]byte{[]byte("iavlStoreKey"), []byte("prefix2")}, counterpartyID)

	println("[INFO] atomone client:", clientID)

	// --- Build the memo-carrying packet ---
	// Receiver must be zkgm's own proxy address - that's the forward
	// discriminator (see forward.gno's tryForward); the memo's own
	// "receiver" field is the final EVM-side destination.
	memo := `{"forward":{"channel":1,"receiver":"0xaabbccdd","quote_token":"0x11223344","metadata":{"implementation":"0x01","initializer":"0x02"}}}`
	payload := transfer.NewFungibleTokenPacketData("uatone", "100", "atone1sender", zkgm.ProxyAddress().String(), memo)
	payloadBz := payload.ProtoMarshal()

	println("[INFO] payload proto hex:", hex.EncodeToString(payloadBz))

	// Voucher denom this recv will mint, so we can track where the asset
	// actually lands (mirrors the r/onbloc/.../scenario/union/receive/
	// balance-narration style).
	voucherDenom := transfer.NewDenom("uatone", transfer.NewHop(transfer.PortID, clientID)).IBCDenom()
	ufmt.Printf("[INFO] zkgm proxy voucher balance before recv: %d\n", transfer.VoucherBalanceOf(voucherDenom, zkgm.ProxyAddress()))
	ufmt.Println("[EXPECTED] should be 0 (voucher doesn't exist yet)")

	specs := ics23.IavlSpec()
	recvPacket := types.MsgRecvPacket{
		Packet: types.Packet{
			Sequence:          1,
			SourceClient:      counterpartyID,
			DestinationClient: clientID,
			TimeoutTimestamp:  timeoutTimestamp,
			Payloads: []types.Payload{{
				SourcePort:      transfer.PortID,
				DestinationPort: transfer.PortID,
				Encoding:        transfer.EncodingProtobuf,
				Value:           payloadBz,
				Version:         transfer.V1,
			}},
		},
		// NOTE proof generated by:
		// go run -C ./cmd/gen-proof . 'prefix2' '07-tendermint-42' 'packet' '{"sequence":1,"source_client":"07-tendermint-42","destination_client":"07-tendermint-1","timeout_timestamp":1234571490,"payloads":[{"source_port":"transfer","destination_port":"transfer","encoding":"application/x-protobuf","value":"CgZ1YXRvbmUSAzEwMBoMYXRvbmUxc2VuZGVyIihnMTgycDM3ZDBjeXZzdnFwdjQ5bHF0cGhwajNqc3d3cXR1eWw0cXl5KoYBeyJmb3J3YXJkIjp7ImNoYW5uZWwiOjEsInJlY2VpdmVyIjoiMHhhYWJiY2NkZCIsInF1b3RlX3Rva2VuIjoiMHgxMTIyMzM0NCIsIm1ldGFkYXRhIjp7ImltcGxlbWVudGF0aW9uIjoiMHgwMSIsImluaXRpYWxpemVyIjoiMHgwMiJ9fX0=","version":"ics20-1"}]}'
		ProofCommitment: []ics23.CommitmentProof{
			// iavl proof
			ics23.CommitmentProof_Exist{
				Exist: &ics23.ExistenceProof{
					Key:   []byte("\x70\x72\x65\x66\x69\x78\x32\x30\x37\x2d\x74\x65\x6e\x64\x65\x72\x6d\x69\x6e\x74\x2d\x34\x32\x01\x00\x00\x00\x00\x00\x00\x00\x01"),
					Value: []byte("\x44\xcc\x18\xea\xba\xda\x0a\x19\xa4\x14\x8a\x29\x2f\xd1\x71\xd7\x59\xd8\x92\x96\x36\x4f\x20\xee\xa5\x90\xae\x41\x37\xee\x4b\x26"),
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
			// rootmulti proof
			ics23.CommitmentProof_Exist{
				Exist: &ics23.ExistenceProof{
					Key:   []byte("\x69\x61\x76\x6c\x53\x74\x6f\x72\x65\x4b\x65\x79"),
					Value: []byte("\x81\x41\x47\x89\x32\x57\xb3\xf6\x6a\xb8\x1d\xd6\xfb\xf6\x5f\x03\xc3\x0d\x79\x74\x84\x89\x7a\x98\xc3\x75\x85\x4f\xeb\xdf\x8e\xa7"),
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
		},
		ProofHeight: trustedHeight,
	}
	recvRes := core.RecvPacket(cross(cur), recvPacket)
	if recvRes != types.RESPONSE_SUCCESS {
		panic("expected recv success")
	}
	println("[INFO] recv res:", recvRes)

	// The voucher was minted then immediately escrowed into zkgm's proxy via
	// SendWithCallback (TransferFrom) - this is the actual asset movement the
	// forward produced.
	ufmt.Printf("[INFO] zkgm proxy voucher balance after recv: %d\n", transfer.VoucherBalanceOf(voucherDenom, zkgm.ProxyAddress()))
	ufmt.Println("[EXPECTED] should be 100 (minted to transfer's own realm, then escrowed into zkgm's proxy by the forward send)")

	// The AtomOne packet's ack must still be pending: transfer.OnRecvPacket
	// deferred it (PacketStatus_Async) instead of writing one synchronously.
	println("[INFO] atomone packet ack (should be pending):", core.Render("clients/"+clientID+"/packet_acknowledgements/1"))
}

// Output:
// [INFO] union channel opened: 1
// [INFO] atomone client: 07-tendermint-1
// [INFO] payload proto hex: 0a067561746f6e6512033130301a0c61746f6e653173656e6465722228673138327033376430637976737671707634396c71747068706a336a737777717475796c347179792a86017b22666f7277617264223a7b226368616e6e656c223a312c227265636569766572223a2230786161626263636464222c2271756f74655f746f6b656e223a2230783131323233333434222c226d65746164617461223a7b22696d706c656d656e746174696f6e223a2230783031222c22696e697469616c697a6572223a2230783032227d7d7d
// [INFO] zkgm proxy voucher balance before recv: 0
// [EXPECTED] should be 0 (voucher doesn't exist yet)
// [INFO] recv res: (2 gno.land/p/aib/ibc/types.ResponseResultType)
// [INFO] zkgm proxy voucher balance after recv: 100
// [EXPECTED] should be 100 (minted to transfer's own realm, then escrowed into zkgm's proxy by the forward send)
// [INFO] atomone packet ack (should be pending): {"error":"sequence 1 not found"}
