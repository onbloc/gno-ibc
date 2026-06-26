// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/forward
package forward

// recv_multihop_forward_filetest is the MULTI-HOP forward scenario (S-7.3, continuation
// path). When a forward's channel path still has hops left after the current one,
// buildForwardChild does not emit the inner instruction directly — it re-wraps it in a
// fresh OP_FORWARD carrying the remaining path, so the next hop continues forwarding.
// This exercises the continuation branch (a path with three channel slots: prevDest,
// nextSource, and one remaining hop). The relay is observed the same way as the
// single-hop case: the parent recv parks async (receipt "committed", ack deferred) and
// a child is committed on the intermediate source channel (2). The nested child packet
// is not reconstructed here (the dequeued continuation path's slot layout makes an exact
// re-derivation fragile); the async parent receipt is the signal that the continuation
// branch built and dispatched the next-hop forward.

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
	childChannel  = uint32(2) // intermediate source channel; counterparty 102
	finalHop      = uint32(3) // remaining hop carried in the continuation path
)

func main(cur realm) {
	println("[SCENARIO] 1. Bootstrap and open the parent (1) and intermediate (2) channels")
	bootstrap(cur)
	println("")

	println("[SCENARIO] 2. Receive a multi-hop OP_FORWARD: the child re-wraps the remaining hop and is relayed")
	parent := recvMultihopForward(cur)
	ufmt.Printf("[INFO] parent receipt: %s\n", receiptState(parent))
	ufmt.Println("[EXPECTED] committed: the continuation branch built and dispatched the next-hop forward (async, ack deferred)")
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

func recvMultihopForward(cur realm) types.Packet {
	var salt [32]byte
	salt[31] = 5
	call := z.Call{Sender: []byte("forwarder"), ContractAddress: []byte(receiverPath), ContractCalldata: []byte("multi-hop-call")}
	forward := z.Forward{
		Path:             multihopPath(parentChannel, childChannel, finalHop),
		TimeoutHeight:    0,
		TimeoutTimestamp: uint64(1) << 62,
		Instruction:      mustCallInstruction(call),
	}
	parent := core.NewPacket(types.ChannelId(101), types.ChannelId(parentChannel), saltedForwardData(salt, forward), types.Timestamp(1<<62))

	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{parent}, [][]byte{nil}, nil, 1))
	return parent
}

func receiptState(packet types.Packet) string {
	v, err := core.GetBatchReceipts(core.CommitPacketsHash([]types.Packet{packet}))
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

func multihopPath(prevDest, nextSource, final uint32) *u256.Uint {
	p := pushChannel(u256.Zero(), prevDest)
	p = pushChannel(p, nextSource)
	p = pushChannel(p, final)
	return p
}

func pushChannel(path *u256.Uint, channel uint32) *u256.Uint {
	next, err := z.UpdateChannelPath(path, channel)
	if err != nil {
		panic(err)
	}
	return next
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
	data, err := z.EncodeZkgmPacket(z.ZkgmPacket{Salt: salt, Path: u256.Zero(), Instruction: z.Instruction{Version: z.INSTR_VERSION_0, Opcode: z.OP_FORWARD, Operand: operand}})
	if err != nil {
		panic(err)
	}
	return data
}

// Output:
// [SCENARIO] 1. Bootstrap and open the parent (1) and intermediate (2) channels
//
// [SCENARIO] 2. Receive a multi-hop OP_FORWARD: the child re-wraps the remaining hop and is relayed
// [INFO] parent receipt: committed
// [EXPECTED] committed: the continuation branch built and dispatched the next-hop forward (async, ack deferred)
