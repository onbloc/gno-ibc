// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/forward
package forward

// Two different parent packets (different outer timeout) derive the SAME
// forward child. core.SendPacket would panic on the second one
// (ErrPacketCommitmentAlreadyExists), unrecoverable across the cross(rlm)
// boundary on-chain, so verifyForwardChannel rejects it first. Each parent's
// own receipt state must differ to prove rejection rather than a silent
// pass-through: the first stays "committed" (async, ack deferred); the
// duplicate is "ack-written" immediately with the universal error ack.

import (
	"chain"
	"testing"

	"gno.land/p/nt/ufmt/v0"
	types "gno.land/p/onbloc/ibc/union/types"
	z "gno.land/p/onbloc/ibc/union/zkgm"

	u256 "gno.land/p/onbloc/math/uint256"

	mocklc "gno.land/r/onbloc/ibc/testing/mock/lightclient"
	"gno.land/r/onbloc/ibc/union/access"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	_ "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	core "gno.land/r/onbloc/ibc/union/core"
	_ "gno.land/r/onbloc/ibc/union/core/v1"
)

const (
	coreImplPathDup  = "gno.land/r/onbloc/ibc/union/core/v1"
	zkgmImplPathDup  = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	mockLcPkgPathDup = "gno.land/r/onbloc/ibc/testing/mock/lightclient"
	receiverPathDup  = "gno.land/r/onbloc/ibc/testing/mock/receiver"

	adminAddrDup = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")

	parentChannelDup = uint32(1) // local parent channel; counterparty 101
	childChannelDup  = uint32(2) // local child source channel; counterparty 102
)

func main(cur realm) {
	println("[SCENARIO] 1. Bootstrap and open the parent (1) and child source (2) channels")
	bootstrapDup(cur)
	println("")

	salt := [32]byte{9}
	forward := z.Forward{
		Path:             forwardPathDup(parentChannelDup, childChannelDup),
		TimeoutTimestamp: uint64(1) << 62,
		Instruction:      mustCallInstructionDup(z.Call{Sender: []byte("forwarder"), ContractAddress: []byte(receiverPathDup), ContractCalldata: []byte("forwarded-call")}),
	}
	child := deriveChildDup(salt, forward)

	println("[SCENARIO] 2. Receive a first OP_FORWARD: the child is relayed, parent ack deferred")
	parent1 := core.NewPacket(types.ChannelId(101), types.ChannelId(parentChannelDup), saltedForwardDataDup(salt, forward), types.Timestamp(1<<62))
	recvForwardDup(cur, parent1)
	ufmt.Printf("[INFO] child committed: %t, parent1 receipt state: %s\n", committedDup(child), receiptStateDup(parent1))
	println("")

	println("[SCENARIO] 3. A second, DIFFERENT parent packet derives the SAME child: rejected synchronously, not panicked")
	// Same salt/path/instruction (so the same child), but a different outer
	// timeout, so this parent packet is not itself a duplicate at the receipt
	// level -- only the derived child collides.
	parent2 := core.NewPacket(types.ChannelId(101), types.ChannelId(parentChannelDup), saltedForwardDataDup(salt, forward), types.Timestamp((1<<62)+1))
	recvForwardDup(cur, parent2)
	ufmt.Printf("[INFO] child commitment unchanged: %t, parent2 receipt state: %s\n", committedDup(child), receiptStateDup(parent2))
	ufmt.Printf("[INFO] parent2's committed ack is exactly zkgm's universal error ack: %t\n", ackedWithDup(parent2, universalErrorAckDup()))
	ufmt.Println("[EXPECTED] parent1 is committed (async, ack deferred); parent2 is ack-written with the universal error ack -- proving the rejection, not a silent pass-through")
}

func bootstrapDup(cur realm) {
	testing.SetRealm(testing.NewUserRealm(adminAddrDup))
	core.UpdateImpl(cross(cur), coreImplPathDup)
	zkgm.UpdateImpl(cross(cur), zkgmImplPathDup)
	zkgm.SetRateLimitDisabled(cross(cur), true)
	zkgm.RegisterCoreApp(cross(cur))
	access.GrantRole(cross(cur), access.RelayerRole, adminAddrDup)
	access.GrantRole(cross(cur), access.RelayerRole, chain.PackageAddress(mockLcPkgPathDup))

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

func recvForwardDup(cur realm, parent types.Packet) {
	testing.SetRealm(testing.NewUserRealm(adminAddrDup))
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{parent}, [][]byte{nil}, nil, 1))
}

// deriveChildDup reconstructs the single-hop child packet exactly as
// buildForwardChild would, so its commitment key can be looked up.
func deriveChildDup(parentSalt [32]byte, forward z.Forward) types.Packet {
	childData := mustZkgmPacketDataDup(z.ZkgmPacket{
		Salt:        z.DeriveForwardSalt(parentSalt),
		Path:        forwardPathDup(parentChannelDup, childChannelDup),
		Instruction: forward.Instruction,
	})
	return core.NewPacket(types.ChannelId(childChannelDup), types.ChannelId(102), childData, types.Timestamp(forward.TimeoutTimestamp))
}

func forwardPathDup(prevDest, nextSource uint32) *u256.Uint {
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

func committedDup(packet types.Packet) bool {
	_, err := core.GetBatchPackets(core.CommitPacketsHash([]types.Packet{packet}))
	return err == nil
}

// receiptStateDup labels a packet's receipt commitment: "none", "committed"
// (ack deferred), "acknowledged", or "ack-written" (a real ack was committed).
func receiptStateDup(packet types.Packet) string {
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

// ackedWithDup reports whether packet's committed ack matches ack exactly,
// compared as commitment hashes since only the hash is stored on-chain.
func ackedWithDup(packet types.Packet, ack []byte) bool {
	v, err := core.GetBatchReceipts(core.CommitPacketsHash([]types.Packet{packet}))
	if err != nil {
		return false
	}
	return v == types.CommitAcks([][]byte{ack})
}

// universalErrorAckDup reconstructs zkgm's universal error ack: the same
// value both dispatchExecutePacket's recover and pre-check failures write.
func universalErrorAckDup() []byte {
	ack, err := z.EncodeAck(z.Ack{Tag: u256.NewUint(0), InnerAck: []byte{}})
	if err != nil {
		panic(err)
	}
	return ack
}

func mustCallInstructionDup(call z.Call) z.Instruction {
	operand, err := z.EncodeCall(call)
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_0, Opcode: z.OP_CALL, Operand: operand}
}

func saltedForwardDataDup(salt [32]byte, forward z.Forward) []byte {
	operand, err := z.EncodeForward(forward)
	if err != nil {
		panic(err)
	}
	return mustZkgmPacketDataDup(z.ZkgmPacket{Salt: salt, Path: u256.Zero(), Instruction: z.Instruction{Version: z.INSTR_VERSION_0, Opcode: z.OP_FORWARD, Operand: operand}})
}

func mustZkgmPacketDataDup(zp z.ZkgmPacket) []byte {
	data, err := z.EncodeZkgmPacket(zp)
	if err != nil {
		panic(err)
	}
	return data
}

// Output:
// [SCENARIO] 1. Bootstrap and open the parent (1) and child source (2) channels
//
// [SCENARIO] 2. Receive a first OP_FORWARD: the child is relayed, parent ack deferred
// [INFO] child committed: true, parent1 receipt state: committed
//
// [SCENARIO] 3. A second, DIFFERENT parent packet derives the SAME child: rejected synchronously, not panicked
// [INFO] child commitment unchanged: true, parent2 receipt state: ack-written
// [INFO] parent2's committed ack is exactly zkgm's universal error ack: true
// [EXPECTED] parent1 is committed (async, ack deferred); parent2 is ack-written with the universal error ack -- proving the rejection, not a silent pass-through
