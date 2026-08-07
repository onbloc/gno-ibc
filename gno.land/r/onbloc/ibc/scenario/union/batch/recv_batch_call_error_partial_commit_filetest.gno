// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/batch
package batch

// recv_batch_call_error_partial_commit_filetest: non-panic counterpart to
// recv_batch_call_panic_full_revert. A Call child returning a plain Go error
// (not a panic) gets a normal failure ack (call.go:85-86), not
// ACK_ERR_ONLY_MAKER, so executeBatch doesn't abort (batch.go:41-59): the
// sibling TokenOrder mint commits.
//
// Also asserts the settled outer ack's commitment is byte-identical to a
// reconstructed SUCCESS batch ack wrapping [TokenOrder success, Call
// failure], via CommitAcks hash comparison — PacketAcknowledgementPath and
// BatchReceiptsPath(CommitPacket(_)) are the same slot, so no new getter is
// needed.

import (
	"chain"
	"encoding/hex"
	"testing"

	"gno.land/p/nt/ufmt/v0"
	types "gno.land/p/onbloc/ibc/union/types"
	z "gno.land/p/onbloc/ibc/union/zkgm"

	u256 "gno.land/p/onbloc/math/uint256"

	mocklc "gno.land/r/onbloc/ibc/testing/mock/lightclient"
	mockrcv "gno.land/r/onbloc/ibc/testing/mock/receiver"
	"gno.land/r/onbloc/ibc/union/access"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	_ "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	core "gno.land/r/onbloc/ibc/union/core"
	_ "gno.land/r/onbloc/ibc/union/core/v1"
)

const (
	coreImplPath  = "gno.land/r/onbloc/ibc/union/core/v1"
	zkgmImplPath  = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	mockLcPkgPath = "gno.land/r/onbloc/ibc/testing/mock/lightclient"
	receiverPath  = "gno.land/r/onbloc/ibc/testing/mock/receiver"

	adminAddr    = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
	receiverAddr = address("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm")
)

func main(cur realm) {
	println("[SCENARIO] 1. Bootstrap IBC host, open a channel, and arm the mock receiver to error (not panic)")
	channelId := bootstrap(cur)
	println("")

	meta := mustTokenMetadata("af739f34ddf951cbc24fdbba4f76213688e13627", z.TokenInitializer{Name: "Gno Token", Symbol: "GNOT", Decimals: 6})
	quoteToken := z.PredictWrappedTokenV2(u256.Zero(), uint32(channelId), []byte("ugnot"), z.MetadataImage(mustDecodeMeta(meta)))

	println("[SCENARIO] 2. Receive an OP_BATCH of [INITIALIZE TokenOrder, OP_CALL(errors)]: the TokenOrder still commits")
	recvBatchWithErroringCall(cur, channelId, quoteToken, meta)
}

func bootstrap(cur realm) types.ChannelId {
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.UpdateImpl(cross(cur), coreImplPath)
	zkgm.UpdateImpl(cross(cur), zkgmImplPath)
	zkgm.SetRateLimitDisabled(cross(cur), true)
	zkgm.RegisterCoreApp(cross(cur))
	access.GrantRole(cross(cur), access.RelayerRole, adminAddr)
	access.GrantRole(cross(cur), access.RelayerRole, chain.PackageAddress(mockLcPkgPath))

	mocklc.RegisterMockLightClient(cross(cur))
	core.CreateClient(cross(cur), core.NewMsgCreateClient(mocklc.MockClientType, nil, nil))
	clientId := types.ClientId(1)

	core.ConnectionOpenInit(cross(cur), core.NewMsgConnectionOpenInit(clientId, types.ClientId(99)))
	connectionId := types.ConnectionId(1)
	core.ConnectionOpenAck(cross(cur), core.NewMsgConnectionOpenAck(connectionId, types.ConnectionId(77), nil, 1))

	portId := []byte(zkgm.ProxyPkgPath())
	core.ChannelOpenInit(cross(cur), core.NewMsgChannelOpenInit(portId, portId, connectionId, zkgm.Version, "g1relayer"))
	channelId := types.ChannelId(1)
	core.ChannelOpenAck(cross(cur), core.NewMsgChannelOpenAck(channelId, zkgm.Version, types.ChannelId(2), nil, 1, "g1relayer"))

	// arm a plain error, not SetPanic (that's the full-revert scenario)
	mockrcv.Reset(cross(cur))
	mockrcv.SetError(cross(cur), "receiver rejected the call")
	return channelId
}

func recvBatchWithErroringCall(cur realm, channelId types.ChannelId, quoteToken string, meta []byte) {
	batch := z.Batch{Instructions: []z.Instruction{
		// child 0: mints unconditionally regardless of the sibling's outcome
		mustOrderInstruction(z.TokenOrderV2{
			Sender:      []byte("remote-sender"),
			Receiver:    []byte(receiverAddr.String()),
			BaseToken:   []byte("ugnot"),
			BaseAmount:  u256.NewUint(100),
			QuoteToken:  []byte(quoteToken),
			QuoteAmount: u256.NewUint(100),
			Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
			Metadata:    meta,
		}),
		// child 1: errors (not panics) -> plain failure ack
		mustCallInstruction(z.Call{
			Sender:           []byte("remote-sender"),
			ContractAddress:  []byte(receiverPath),
			ContractCalldata: []byte("reject-me"),
		}),
	}}
	packet := core.NewPacket(types.ChannelId(2), channelId, mustPacketData(mustBatchInstruction(batch)), types.Timestamp(1<<62))

	voucherBefore := zkgm.VoucherBalanceOf(quoteToken, receiverAddr)

	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{packet}, [][]byte{nil}, nil, 1))

	expectedOuterAck := expectedBatchOuterAck([][]byte{
		expectedTokenOrderProtocolSuccessAck(),
		expectedCallErrAck("receiver rejected the call"),
	})

	ufmt.Printf("[INFO] TokenOrder child: receiver voucher %d -> %d\n", voucherBefore, zkgm.VoucherBalanceOf(quoteToken, receiverAddr))
	ufmt.Printf("[INFO] Call child: mock receiver OnZkgm calls = %d, calldata = %q\n", mockrcv.Calls(cross(cur)), mockrcv.LastCalldata(cross(cur)))
	ufmt.Printf("[INFO] packet receipt recorded: %t\n", receiptRecorded(packet))
	ufmt.Printf("[INFO] settled outer ack bytes-equal SUCCESS batch [TokenOrder=SUCCESS, Call=FAILURE]: %t\n", ackCommitmentEquals(packet, expectedOuterAck))
	ufmt.Println("[EXPECTED] no panic; TokenOrder mints 100; Call receiver runs once and its error becomes a plain failure ack, not ACK_ERR_ONLY_MAKER; receipt recorded")
	ufmt.Println("[EXPECTED] settled outer ack should be byte-identical to a SUCCESS batch ack wrapping [TokenOrder success, Call failure]")
}

func receiptRecorded(packet types.Packet) bool {
	_, err := core.GetBatchReceipts(core.CommitPacketsHash([]types.Packet{packet}))
	return err == nil
}

// ackCommitmentEquals reports whether the packet's settled acknowledgement is
// byte-identical to expectedAck. Only the ack's commitment (a hash) is ever
// stored — PacketAcknowledgementPath is BatchReceiptsPath(CommitPacket(packet))
// (types/path.gno), the same slot receiptRecorded reads — so the comparison
// recomputes the same hash locally via types.CommitAcks and compares
// commitments.
func ackCommitmentEquals(packet types.Packet, expectedAck []byte) bool {
	commitment, err := core.GetBatchReceipts(core.CommitPacketsHash([]types.Packet{packet}))
	if err != nil {
		return false
	}
	return commitment == types.CommitAcks([][]byte{expectedAck})
}

// expectedTokenOrderProtocolSuccessAck mirrors the v1 impl's unexported
// encodeTokenOrderSuccessAck(fillTypeProtocol(), nil) (token_order.gno): the
// INITIALIZE child protocol-fills (base==quote==100, no relayer fee), so its
// own ack is a plain protocol-fill success with no MarketMaker.
func expectedTokenOrderProtocolSuccessAck() []byte {
	innerAck, err := z.EncodeTokenOrderAck(z.TokenOrderAck{FillType: z.Uint256FromBytes32(z.FILL_TYPE_PROTOCOL)})
	if err != nil {
		panic(err)
	}
	ack, err := z.EncodeAck(z.Ack{Tag: z.Uint256FromBytes32(z.TAG_ACK_SUCCESS), InnerAck: innerAck})
	if err != nil {
		panic(err)
	}
	return ack
}

// expectedCallErrAck mirrors the v1 impl's unexported callErrAck() (call.go):
// Ack{Tag: FAILURE, InnerAck: err.Error()}, ABI-encoded.
func expectedCallErrAck(errMsg string) []byte {
	ack, err := z.EncodeAck(z.Ack{Tag: z.Uint256FromBytes32(z.TAG_ACK_FAILURE), InnerAck: []byte(errMsg)})
	if err != nil {
		panic(err)
	}
	return ack
}

// expectedBatchOuterAck mirrors executeBatch's outer wrapping (batch.gno:63-71):
// a SUCCESS-tagged Ack whose InnerAck is the ABI-encoded BatchAck of the
// child acks, in child order — regardless of whether an individual child's
// own ack tag is SUCCESS or FAILURE.
func expectedBatchOuterAck(childAcks [][]byte) []byte {
	batchAckBytes, err := z.EncodeBatchAck(z.BatchAck{Acknowledgements: childAcks})
	if err != nil {
		panic(err)
	}
	ack, err := z.EncodeAck(z.Ack{Tag: z.Uint256FromBytes32(z.TAG_ACK_SUCCESS), InnerAck: batchAckBytes})
	if err != nil {
		panic(err)
	}
	return ack
}

// --- encoding helpers ---

func mustOrderInstruction(order z.TokenOrderV2) z.Instruction {
	operand, err := z.EncodeTokenOrderV2(order)
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_2, Opcode: z.OP_TOKEN_ORDER, Operand: operand}
}

func mustCallInstruction(call z.Call) z.Instruction {
	operand, err := z.EncodeCall(call)
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_0, Opcode: z.OP_CALL, Operand: operand}
}

func mustBatchInstruction(b z.Batch) z.Instruction {
	operand, err := z.EncodeBatch(b)
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_0, Opcode: z.OP_BATCH, Operand: operand}
}

func mustPacketData(instr z.Instruction) []byte {
	data, err := z.EncodeZkgmPacket(z.ZkgmPacket{Path: u256.Zero(), Instruction: instr})
	if err != nil {
		panic(err)
	}
	return data
}

func mustTokenMetadata(implementationHex string, ti z.TokenInitializer) []byte {
	implementation, err := hex.DecodeString(implementationHex)
	if err != nil {
		panic(err)
	}
	initBytes, err := z.EncodeTokenInitializer(ti)
	if err != nil {
		panic(err)
	}
	meta, err := z.EncodeTokenMetadata(z.TokenMetadata{Implementation: implementation, Initializer: initBytes})
	if err != nil {
		panic(err)
	}
	return meta
}

func mustDecodeMeta(bz []byte) z.TokenMetadata {
	meta, err := z.DecodeTokenMetadata(bz)
	if err != nil {
		panic(err)
	}
	return meta
}

// Output:
// [SCENARIO] 1. Bootstrap IBC host, open a channel, and arm the mock receiver to error (not panic)
//
// [SCENARIO] 2. Receive an OP_BATCH of [INITIALIZE TokenOrder, OP_CALL(errors)]: the TokenOrder still commits
// [INFO] TokenOrder child: receiver voucher 0 -> 100
// [INFO] Call child: mock receiver OnZkgm calls = 1, calldata = "reject-me"
// [INFO] packet receipt recorded: true
// [INFO] settled outer ack bytes-equal SUCCESS batch [TokenOrder=SUCCESS, Call=FAILURE]: true
// [EXPECTED] no panic; TokenOrder mints 100; Call receiver runs once and its error becomes a plain failure ack, not ACK_ERR_ONLY_MAKER; receipt recorded
// [EXPECTED] settled outer ack should be byte-identical to a SUCCESS batch ack wrapping [TokenOrder success, Call failure]
