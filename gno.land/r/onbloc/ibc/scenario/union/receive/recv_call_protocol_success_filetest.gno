// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/receive
package receive

// recv_call_protocol_success_filetest: a standalone (non-batch) OP_CALL
// packet whose receiver returns nil. Paired with
// recv_call_receiver_error_settles_failure_ack, this closes both normal
// (non-panic) branches of a direct, non-batch Call recv.
//
// What THIS file covers: the top-level OP_CALL case in dispatchExecutePacket
// (dispatch.gno) reached directly, not nested inside OP_BATCH — proving
// standalone dispatch routing and receipt commit work outside a batch.
//
// What it does NOT cover: a success ack can't accidentally collide with
// ACK_ERR_ONLY_MAKER's byte pattern, so this path gives OnRecvPacket's
// isOnlyMakerAck check (unlike in the error-path sibling) no realistic chance
// to catch a real bug. Also asserts the settled ack's commitment is
// byte-identical to callSuccessAck()'s output (via CommitAcks hash
// comparison — PacketAcknowledgementPath and BatchReceiptsPath(CommitPacket(_))
// are the same slot, so no new getter is needed).

import (
	"chain"
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

	adminAddr = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
)

func main(cur realm) {
	println("[SCENARIO] 1. Bootstrap IBC host, open a channel, and reset the mock receiver")
	channelId := bootstrap(cur)
	println("")

	println("[SCENARIO] 2. Receive a standalone OP_CALL: receiver succeeds, success ack settles")
	recvStandaloneSuccessfulCall(cur, channelId)
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

	// no SetError/SetPanic: OnZkgm returns nil, the plain success path
	mockrcv.Reset(cross(cur))
	return channelId
}

func recvStandaloneSuccessfulCall(cur realm, channelId types.ChannelId) {
	call := z.Call{
		Sender:           []byte("remote-sender"),
		ContractAddress:  []byte(receiverPath),
		ContractCalldata: []byte("do-something"),
	}
	packet := core.NewPacket(types.ChannelId(2), channelId, mustPacketData(mustCallInstruction(call)), types.Timestamp(1<<62))

	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{packet}, [][]byte{nil}, nil, 1))

	ufmt.Printf("[INFO] mock receiver OnZkgm calls = %d, calldata = %q\n", mockrcv.Calls(cross(cur)), mockrcv.LastCalldata(cross(cur)))
	ufmt.Printf("[INFO] packet receipt recorded: %t\n", receiptRecorded(packet))
	ufmt.Printf("[INFO] settled ack bytes-equal callSuccessAck(): %t\n", ackCommitmentEquals(packet, expectedCallSuccessAck()))
	ufmt.Println("[EXPECTED] no panic; receiver ran once; a success ack settles; receipt recorded")
	ufmt.Println("[EXPECTED] settled ack should be byte-identical to callSuccessAck()'s output")
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

// expectedCallSuccessAck mirrors the v1 impl's unexported callSuccessAck()
// (call.go): Ack{Tag: SUCCESS, InnerAck: empty}, ABI-encoded.
func expectedCallSuccessAck() []byte {
	ack, err := z.EncodeAck(z.Ack{Tag: z.Uint256FromBytes32(z.TAG_ACK_SUCCESS), InnerAck: []byte{}})
	if err != nil {
		panic(err)
	}
	return ack
}

// --- encoding helpers ---

func mustCallInstruction(call z.Call) z.Instruction {
	operand, err := z.EncodeCall(call)
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_0, Opcode: z.OP_CALL, Operand: operand}
}

func mustPacketData(instr z.Instruction) []byte {
	data, err := z.EncodeZkgmPacket(z.ZkgmPacket{Path: u256.Zero(), Instruction: instr})
	if err != nil {
		panic(err)
	}
	return data
}

// Output:
// [SCENARIO] 1. Bootstrap IBC host, open a channel, and reset the mock receiver
//
// [SCENARIO] 2. Receive a standalone OP_CALL: receiver succeeds, success ack settles
// [INFO] mock receiver OnZkgm calls = 1, calldata = "do-something"
// [INFO] packet receipt recorded: true
// [INFO] settled ack bytes-equal callSuccessAck(): true
// [EXPECTED] no panic; receiver ran once; a success ack settles; receipt recorded
// [EXPECTED] settled ack should be byte-identical to callSuccessAck()'s output
