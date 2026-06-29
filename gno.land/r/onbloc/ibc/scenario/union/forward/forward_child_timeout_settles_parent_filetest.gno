// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/forward
package forward

// forward_child_timeout_settles_parent_filetest is the TIMEOUT-resolution forward
// scenario (S-5.4). A forward parks the parent in-flight and relays the child. If the
// child is never received and times out, the impl's OnTimeoutPacket routes through
// handleForwardChild, which settles the parked parent with the universal-error
// acknowledgement — propagating the failure back upstream so the original sender is
// refunded on the source chain. This file relays a child whose timeout the light
// client's clock has already passed, proves the child timeout, and verifies the parent
// receipt moves committed (ack deferred) -> ack-written (universal-error settled) while
// the child's commitment moves committed -> acknowledged. It mirrors the ack-resolution
// path (S-6.2) but through OnTimeoutPacket instead of OnAcknowledgementPacket.

import (
	"chain"
	"testing"

	"gno.land/p/nt/ufmt/v0"
	types "gno.land/p/onbloc/ibc/union/types"
	z "gno.land/p/onbloc/ibc/union/zkgm"

	u256 "gno.land/p/gnoswap/uint256"

	"gno.land/r/onbloc/ibc/union/access"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	_ "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	core "gno.land/r/onbloc/ibc/union/core"
	_ "gno.land/r/onbloc/ibc/union/core/v1"
	mocklc "gno.land/r/onbloc/ibc/testing/mock/lightclient"
)

const (
	coreImplPath  = "gno.land/r/onbloc/ibc/union/core/v1"
	zkgmImplPath  = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	mockLcPkgPath = "gno.land/r/onbloc/ibc/testing/mock/lightclient"
	receiverPath  = "gno.land/r/onbloc/ibc/testing/mock/receiver"

	adminAddr = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")

	parentChannel = uint32(1) // local parent channel; counterparty 101
	childChannel  = uint32(2) // local child source channel; counterparty 102

	// The mock light client reports timestamp 1, so a child timeout of 1 is already
	// reached and the child can be proven timed out immediately.
	childTimeout = uint64(1)
)

func main(cur realm) {
	println("[SCENARIO] 1. Bootstrap and open the parent (1) and child source (2) channels")
	bootstrap(cur)
	println("")

	salt := saltSeed(9)
	forward := buildForward()
	parent := core.NewPacket(types.ChannelId(101), types.ChannelId(parentChannel), saltedForwardData(salt, forward), types.Timestamp(1<<62))
	child := deriveChild(salt, forward)

	println("[SCENARIO] 2. Receive the OP_FORWARD: parent parked in-flight (async), child relayed")
	recvForward(cur, parent)
	ufmt.Printf("[INFO] after recv    -> parent receipt: %s, child commitment: %s\n", receiptState(parent), sendState(child))
	ufmt.Println("[EXPECTED] parent receipt committed (ack deferred), child committed (relayed)")
	println("")

	println("[SCENARIO] 3. The child times out: handleForwardChild settles the parent with the universal-error ack")
	timeoutChild(cur, child)
	ufmt.Printf("[INFO] after timeout -> parent receipt: %s, child commitment: %s\n", receiptState(parent), sendState(child))
	ufmt.Println("[EXPECTED] parent receipt ack-written (universal-error settled upstream), child acknowledged")
}

func bootstrap(cur realm) {
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
	core.ChannelOpenAck(cross(cur), core.NewMsgChannelOpenAck(types.ChannelId(1), zkgm.Version, types.ChannelId(101), nil, 1, "g1relayer"))
	core.ChannelOpenInit(cross(cur), core.NewMsgChannelOpenInit(portId, portId, connectionId, zkgm.Version, "g1relayer"))
	core.ChannelOpenAck(cross(cur), core.NewMsgChannelOpenAck(types.ChannelId(2), zkgm.Version, types.ChannelId(102), nil, 1, "g1relayer"))
}

func recvForward(cur realm, parent types.Packet) {
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{parent}, [][]byte{nil}, nil, 1))
}

func timeoutChild(cur realm, child types.Packet) {
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketTimeout(cross(cur), types.NewMsgPacketTimeout(child, nil, 1))
}

func buildForward() z.Forward {
	call := z.Call{Sender: []byte("forwarder"), ContractAddress: []byte(receiverPath), ContractCalldata: []byte("forwarded-call")}
	return z.Forward{
		Path:             forwardPath(parentChannel, childChannel),
		TimeoutHeight:    0,
		TimeoutTimestamp: childTimeout,
		Instruction:      mustCallInstruction(call),
	}
}

func deriveChild(parentSalt [32]byte, forward z.Forward) types.Packet {
	childData := mustZkgmPacketData(z.ZkgmPacket{
		Salt:        z.DeriveForwardSalt(parentSalt),
		Path:        forwardPath(parentChannel, childChannel),
		Instruction: forward.Instruction,
	})
	return core.NewPacket(types.ChannelId(childChannel), types.ChannelId(102), childData, types.Timestamp(forward.TimeoutTimestamp))
}

// --- commitment observation ---

func receiptState(packet types.Packet) string {
	v, err := core.GetBatchReceipts(core.CommitPacketsHash([]types.Packet{packet}))
	return commitLabel(v, err)
}

func sendState(packet types.Packet) string {
	v, err := core.GetBatchPackets(core.CommitPacketsHash([]types.Packet{packet}))
	return commitLabel(v, err)
}

func commitLabel(v types.H256, err error) string {
	if err != nil {
		return "none"
	}
	switch v {
	case types.COMMITMENT_MAGIC:
		return "committed"
	case types.COMMITMENT_MAGIC_ACK:
		return "acknowledged"
	default:
		return "ack-written"
	}
}

// --- encoding helpers ---

func saltSeed(b byte) [32]byte {
	var s [32]byte
	s[31] = b
	return s
}

func forwardPath(prevDest, nextSource uint32) *u256.Uint {
	p, err := z.UpdateChannelPath(u256.Zero(), prevDest)
	if err != nil {
		panic(err)
	}
	p, err = z.UpdateChannelPath(p, nextSource)
	if err != nil {
		panic(err)
	}
	return p
}

func mustCallInstruction(call z.Call) z.Instruction {
	operand, err := z.EncodeCall(call)
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_0, Opcode: z.OP_CALL, Operand: operand}
}

func saltedForwardData(salt [32]byte, forward z.Forward) []byte {
	operand, err := z.EncodeForward(forward)
	if err != nil {
		panic(err)
	}
	return mustZkgmPacketData(z.ZkgmPacket{Salt: salt, Path: u256.Zero(), Instruction: z.Instruction{Version: z.INSTR_VERSION_0, Opcode: z.OP_FORWARD, Operand: operand}})
}

func mustZkgmPacketData(zp z.ZkgmPacket) []byte {
	data, err := z.EncodeZkgmPacket(zp)
	if err != nil {
		panic(err)
	}
	return data
}

// Output:
// [SCENARIO] 1. Bootstrap and open the parent (1) and child source (2) channels
//
// [SCENARIO] 2. Receive the OP_FORWARD: parent parked in-flight (async), child relayed
// [INFO] after recv    -> parent receipt: committed, child commitment: committed
// [EXPECTED] parent receipt committed (ack deferred), child committed (relayed)
//
// [SCENARIO] 3. The child times out: handleForwardChild settles the parent with the universal-error ack
// [INFO] after timeout -> parent receipt: ack-written, child commitment: acknowledged
// [EXPECTED] parent receipt ack-written (universal-error settled upstream), child acknowledged
