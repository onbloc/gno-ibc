// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/receive
package receive

// recv_call_receiver_error_settles_failure_ack_filetest: a standalone
// (non-batch) OP_CALL packet whose receiver returns a plain Go error, not a
// panic. executeCall's safeCallOnZkgm reports panicked=false, so it takes the
// callErrAck branch (call.go:85-86) instead of ACK_ERR_ONLY_MAKER.
//
// What THIS file covers: OnRecvPacket's isOnlyMakerAck check (impl.gno:92) is
// only exercised on a Call's own ack when the Call is NOT wrapped in a batch —
// a batch-wrapped Call is checked earlier, inside executeBatch (batch.go:56),
// before ever reaching OnRecvPacket. Every existing Call test wraps in a
// batch, so this is the only place a wiring bug that mis-flags a plain
// failure ack as only-maker (spurious panic) would surface.
//
// Also asserts the settled ack's commitment is byte-identical to
// callErrAck(err)'s output (via CommitAcks hash comparison —
// PacketAcknowledgementPath and BatchReceiptsPath(CommitPacket(_)) are the
// same slot, so no new getter is needed), closing the gap a bare Calls-count
// check would leave (a bug flipping the tag to SUCCESS wouldn't otherwise
// change any of this file's assertions).

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
	println("[SCENARIO] 1. Bootstrap IBC host, open a channel, and arm the mock receiver to error (not panic)")
	channelId := bootstrap(cur)
	println("")

	println("[SCENARIO] 2. Receive a standalone OP_CALL: receiver errors, no panic, failure ack settles")
	recvStandaloneErroringCall(cur, channelId)
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

	// arm a plain error, not SetPanic (that would abort the recv tx instead)
	mockrcv.Reset(cross(cur))
	mockrcv.SetError(cross(cur), "receiver rejected the call")
	return channelId
}

func recvStandaloneErroringCall(cur realm, channelId types.ChannelId) {
	call := z.Call{
		Sender:           []byte("remote-sender"),
		ContractAddress:  []byte(receiverPath),
		ContractCalldata: []byte("reject-me"),
	}
	packet := core.NewPacket(types.ChannelId(2), channelId, mustPacketData(mustCallInstruction(call)), types.Timestamp(1<<62))

	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{packet}, [][]byte{nil}, nil, 1))

	ufmt.Printf("[INFO] mock receiver OnZkgm calls = %d, calldata = %q\n", mockrcv.Calls(cross(cur)), mockrcv.LastCalldata(cross(cur)))
	ufmt.Printf("[INFO] packet receipt recorded: %t\n", receiptRecorded(packet))
	ufmt.Printf("[INFO] settled ack bytes-equal callErrAck(\"receiver rejected the call\"): %t\n", ackCommitmentEquals(packet, expectedCallErrAck("receiver rejected the call")))
	ufmt.Println("[EXPECTED] no panic; receiver ran once; a failure ack settles instead of ACK_ERR_ONLY_MAKER; receipt recorded")
	ufmt.Println("[EXPECTED] settled ack should be byte-identical to callErrAck(err)'s output")
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

// expectedCallErrAck mirrors the v1 impl's unexported callErrAck() (call.go):
// Ack{Tag: FAILURE, InnerAck: err.Error()}, ABI-encoded.
func expectedCallErrAck(errMsg string) []byte {
	ack, err := z.EncodeAck(z.Ack{Tag: z.Uint256FromBytes32(z.TAG_ACK_FAILURE), InnerAck: []byte(errMsg)})
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
// [SCENARIO] 1. Bootstrap IBC host, open a channel, and arm the mock receiver to error (not panic)
//
// [SCENARIO] 2. Receive a standalone OP_CALL: receiver errors, no panic, failure ack settles
// [INFO] mock receiver OnZkgm calls = 1, calldata = "reject-me"
// [INFO] packet receipt recorded: true
// [INFO] settled ack bytes-equal callErrAck("receiver rejected the call"): true
// [EXPECTED] no panic; receiver ran once; a failure ack settles instead of ACK_ERR_ONLY_MAKER; receipt recorded
// [EXPECTED] settled ack should be byte-identical to callErrAck(err)'s output
