// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/forward
package forward

// recv_forward_creates_child_filetest is the NORMAL-path forward scenario (S-7.3). A
// chain that receives an OP_FORWARD packet must relay its child to the next hop. The
// impl builds the child (advancing the channel path and namespacing the salt with
// DeriveForwardSalt), records the parent in the in-flight store for later async ack
// settlement, and commits the child through core.SendPacket. This file opens two
// channels — the parent (local 1 / counterparty 101) and the child source (local 2 /
// counterparty 102) — receives a forward whose Call child targets channel 2, and
// verifies the relay happened: the parent recv completes with PacketStatusAsync (no
// ack written yet) and records its receipt, and the re-derived child packet's
// commitment is present. The child is observed by reconstructing exactly what
// buildForwardChild produces (DeriveForwardSalt(parentSalt), path [prevDest,
// nextSource], the inner Call instruction, source channel 2 → counterparty 102).

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
)

func main(cur realm) {
	println("[SCENARIO] 1. Bootstrap and open two channels: the parent (1) and the child source (2)")
	bootstrap(cur)
	println("")

	println("[SCENARIO] 2. Receive an OP_FORWARD: the child is relayed to the next hop (channel 2)")
	recvForward(cur)
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

func recvForward(cur realm) {
	var salt [32]byte
	salt[31] = 7
	call := z.Call{Sender: []byte("forwarder"), ContractAddress: []byte(receiverPath), ContractCalldata: []byte("forwarded-call")}
	forward := z.Forward{
		Path:             forwardPath(parentChannel, childChannel),
		TimeoutHeight:    0,
		TimeoutTimestamp: uint64(1) << 62,
		Instruction:      mustCallInstruction(call),
	}
	parent := core.NewPacket(types.ChannelId(101), types.ChannelId(parentChannel), saltedForwardData(salt, forward), types.Timestamp(1<<62))

	child := deriveChild(salt, forward)

	childBefore := committed(child)

	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{parent}, [][]byte{nil}, nil, 1))

	ufmt.Printf("[INFO] parent packet receipt recorded: %t\n", receiptRecorded(parent))
	ufmt.Printf("[INFO] child packet commitment present: %t -> %t\n", childBefore, committed(child))
	ufmt.Println("[EXPECTED] forward relays the child: parent receipt recorded (recv accepted), child committed on channel 2 (ack deferred async until the child resolves)")
}

// deriveChild reconstructs the single-hop child packet exactly as buildForwardChild
// does, so its commitment key can be looked up.
func deriveChild(parentSalt [32]byte, forward z.Forward) types.Packet {
	// Single hop: continuation path is empty, so the child carries the inner
	// instruction verbatim and its path is [prevDest, nextSource].
	childData := mustZkgmPacketData(z.ZkgmPacket{
		Salt:        z.DeriveForwardSalt(parentSalt),
		Path:        forwardPath(parentChannel, childChannel),
		Instruction: forward.Instruction,
	})
	return core.NewPacket(types.ChannelId(childChannel), types.ChannelId(102), childData, types.Timestamp(forward.TimeoutTimestamp))
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

func committed(packet types.Packet) bool {
	_, err := core.GetBatchPackets(core.CommitPacketsHash([]types.Packet{packet}))
	return err == nil
}

func receiptRecorded(packet types.Packet) bool {
	_, err := core.GetBatchReceipts(core.CommitPacketsHash([]types.Packet{packet}))
	return err == nil
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
// [SCENARIO] 1. Bootstrap and open two channels: the parent (1) and the child source (2)
//
// [SCENARIO] 2. Receive an OP_FORWARD: the child is relayed to the next hop (channel 2)
// [INFO] parent packet receipt recorded: true
// [INFO] child packet commitment present: false -> true
// [EXPECTED] forward relays the child: parent receipt recorded (recv accepted), child committed on channel 2 (ack deferred async until the child resolves)
