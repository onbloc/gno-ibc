// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/forward
package forward

// forward_recv_async_lifecycle_filetest pins OP_FORWARD receive semantics:
// malformed forward paths write synchronous failure acks, while valid forwards
// are asynchronous. recv records only the parent receipt and sends the child
// packet; the child timeout later writes the deferred parent ack.

import (
	"chain"
	"testing"

	"gno.land/p/nt/ufmt/v0"
	"gno.land/p/onbloc/ibc/union/types"
	z "gno.land/p/onbloc/ibc/union/zkgm"

	u256 "gno.land/p/gnoswap/uint256"

	"gno.land/r/onbloc/ibc/union/access"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	_ "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"

	"gno.land/r/onbloc/ibc/union/core"
	_ "gno.land/r/onbloc/ibc/union/core/v1"

	mocklc "gno.land/r/onbloc/ibc/testing/mock/lightclient"
)

const (
	coreImplPath  = "gno.land/r/onbloc/ibc/union/core/v1"
	zkgmImplPath  = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	mockLcPkgPath = "gno.land/r/onbloc/ibc/testing/mock/lightclient"

	adminAddr = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
)

func main(cur realm) {
	println("[SCENARIO] 1. Bootstrap IBC host and open a zkgm channel")
	channelId := bootstrap(cur)
	println("")

	println("[SCENARIO] 2. Invalid OP_FORWARD writes a sync failure acknowledgement")
	invalidForwardWritesFailureAck(cur, channelId)
	println("")

	println("[SCENARIO] 3. Valid OP_FORWARD defers parent acknowledgement until child timeout")
	validForwardDefersUntilChildTimeout(cur, channelId)
	println("")

	println("[SCENARIO] 4. Valid OP_FORWARD child acknowledgement resolves parent acknowledgement")
	validForwardDefersUntilChildAck(cur, channelId)
	println("")

	println("[SCENARIO] 5. Multi-hop OP_FORWARD emits a continuation child packet")
	multiHopForwardBuildsContinuationChild(cur, channelId)
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
	return channelId
}

func invalidForwardWritesFailureAck(cur realm, channelId types.ChannelId) {
	parent := forwardPacket(channelId, [32]byte{0x01}, forwardPath(uint32(channelId)))

	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{parent}, [][]byte{nil}, nil, 1))

	ufmt.Printf("[INFO] invalid forward parent sync ack written: %t\n", ackWritten(parent))
	ufmt.Println("[EXPECTED] malformed forward path is rejected with a sync failure ack")
}

func validForwardDefersUntilChildTimeout(cur realm, channelId types.ChannelId) {
	salt := [32]byte{0x02}
	parent := forwardPacket(channelId, salt, forwardPath(uint32(channelId), uint32(channelId)))
	child := forwardedChildPacket(channelId, salt)

	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{parent}, [][]byte{nil}, nil, 1))
	ufmt.Printf("[INFO] valid forward parent is receipt-only after recv: %t\n", receiptOnly(parent))

	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketTimeout(cross(cur), types.NewMsgPacketTimeout(child, nil, 1))
	ufmt.Printf("[INFO] valid forward parent ack written after child timeout: %t\n", ackWritten(parent))
	ufmt.Println("[EXPECTED] valid forward recv is async; the child timeout resolves the parent ack")
}

func validForwardDefersUntilChildAck(cur realm, channelId types.ChannelId) {
	salt := [32]byte{0x03}
	parent := forwardPacket(channelId, salt, forwardPath(uint32(channelId), uint32(channelId)))
	child := forwardedChildPacket(channelId, salt)

	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{parent}, [][]byte{nil}, nil, 1))
	ufmt.Printf("[INFO] valid forward parent is receipt-only after recv: %t\n", receiptOnly(parent))

	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketAcknowledgement(cross(cur), core.NewMsgPacketAcknowledgement([]types.Packet{child}, [][]byte{successAck()}, nil, 1))
	ufmt.Printf("[INFO] valid forward parent ack written after child ack: %t\n", ackWritten(parent))
	ufmt.Printf("[INFO] valid forward parent remains ack written: %t\n", ackWritten(parent))
	ufmt.Println("[EXPECTED] valid forward child ack resolves the deferred parent ack")
}

func multiHopForwardBuildsContinuationChild(cur realm, channelId types.ChannelId) {
	salt := [32]byte{0x04}
	path := forwardPath(uint32(channelId), uint32(channelId), uint32(types.ChannelId(2)), uint32(channelId))
	parent := forwardPacket(channelId, salt, path)
	child := forwardedContinuationChildPacket(channelId, salt)

	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{parent}, [][]byte{nil}, nil, 1))
	zp := mustDecodeZkgmPacket(child)

	ufmt.Printf("[INFO] multi-hop parent is receipt-only after recv: %t\n", receiptOnly(parent))
	ufmt.Printf("[INFO] multi-hop child packet committed: %t\n", packetCommitted(child))
	ufmt.Printf("[INFO] multi-hop child opcode is OP_FORWARD: %t\n", zp.Instruction.Opcode == z.OP_FORWARD)
	ufmt.Printf("[INFO] multi-hop child salt is derived: %t\n", zp.Salt == z.DeriveForwardSalt(salt))
	ufmt.Printf("[INFO] multi-hop child source channel is expected: %t\n", child.SourceChannelId == channelId)
	ufmt.Printf("[INFO] multi-hop child destination channel is expected: %t\n", child.DestinationChannelId == types.ChannelId(2))
	ufmt.Println("[EXPECTED] continuation paths keep forwarding instead of executing the final child")
}

func forwardPacket(channelId types.ChannelId, salt [32]byte, forwardPath *u256.Uint) types.Packet {
	data, err := z.EncodeZkgmPacket(z.ZkgmPacket{
		Salt: salt,
		Path: u256.Zero(),
		Instruction: z.Instruction{
			Version: z.INSTR_VERSION_0,
			Opcode:  z.OP_FORWARD,
			Operand: mustForwardBytes(z.Forward{
				Path:             forwardPath,
				TimeoutTimestamp: 1,
				Instruction:      callInstruction(),
			}),
		},
	})
	if err != nil {
		panic(err)
	}

	return core.NewPacket(types.ChannelId(2), channelId, data, types.Timestamp(1<<62))
}

func forwardedChildPacket(channelId types.ChannelId, parentSalt [32]byte) types.Packet {
	childPath := forwardPath(uint32(channelId), uint32(channelId))
	data, err := z.EncodeZkgmPacket(z.ZkgmPacket{
		Salt:        z.DeriveForwardSalt(parentSalt),
		Path:        childPath,
		Instruction: callInstruction(),
	})
	if err != nil {
		panic(err)
	}

	return core.NewPacket(channelId, types.ChannelId(2), data, types.Timestamp(1))
}

func forwardedContinuationChildPacket(channelId types.ChannelId, parentSalt [32]byte) types.Packet {
	childPath := forwardPath(uint32(channelId), uint32(channelId))
	continuationPath := forwardPath(uint32(types.ChannelId(2)), uint32(channelId))
	data, err := z.EncodeZkgmPacket(z.ZkgmPacket{
		Salt: z.DeriveForwardSalt(parentSalt),
		Path: childPath,
		Instruction: z.Instruction{
			Version: z.INSTR_VERSION_0,
			Opcode:  z.OP_FORWARD,
			Operand: mustForwardBytes(z.Forward{
				Path:             continuationPath,
				TimeoutTimestamp: 1,
				Instruction:      callInstruction(),
			}),
		},
	})
	if err != nil {
		panic(err)
	}

	return core.NewPacket(channelId, types.ChannelId(2), data, types.Timestamp(1))
}

func callInstruction() z.Instruction {
	callBytes, err := z.EncodeCall(z.Call{
		Sender:           []byte("remote-sender"),
		ContractAddress:  []byte("gno.land/r/onbloc/ibc/testing/mock/receiver"),
		ContractCalldata: []byte("forward-child"),
	})
	if err != nil {
		panic(err)
	}

	return z.Instruction{Version: z.INSTR_VERSION_0, Opcode: z.OP_CALL, Operand: callBytes}
}

func successAck() []byte {
	ack, err := z.EncodeAck(z.Ack{Tag: z.Uint256FromBytes32(z.TAG_ACK_SUCCESS), InnerAck: []byte("child-ok")})
	if err != nil {
		panic(err)
	}

	return ack
}

func mustForwardBytes(forward z.Forward) []byte {
	out, err := z.EncodeForward(forward)
	if err != nil {
		panic(err)
	}

	return out
}

func forwardPath(channels ...uint32) *u256.Uint {
	path := u256.Zero()
	for _, channel := range channels {
		var err error
		path, err = z.UpdateChannelPath(path, channel)
		if err != nil {
			panic(err)
		}
	}
	return path
}

func receiptOnly(packet types.Packet) bool {
	commitment, err := core.GetBatchReceipts(core.CommitPacketHash(packet))
	return err == nil && commitment == types.COMMITMENT_MAGIC
}

func ackWritten(packet types.Packet) bool {
	commitment, err := core.GetBatchReceipts(core.CommitPacketHash(packet))
	return err == nil && commitment != types.COMMITMENT_MAGIC
}

func packetCommitted(packet types.Packet) bool {
	commitment, err := core.GetBatchPackets(core.CommitPacketHash(packet))
	return err == nil && commitment == types.COMMITMENT_MAGIC
}

func mustDecodeZkgmPacket(packet types.Packet) z.ZkgmPacket {
	zp, err := z.DecodeZkgmPacket(types.CloneBytes(packet.Data))
	if err != nil {
		panic(err)
	}

	return zp
}

// Output:
// [SCENARIO] 1. Bootstrap IBC host and open a zkgm channel
//
// [SCENARIO] 2. Invalid OP_FORWARD writes a sync failure acknowledgement
// [INFO] invalid forward parent sync ack written: true
// [EXPECTED] malformed forward path is rejected with a sync failure ack
//
// [SCENARIO] 3. Valid OP_FORWARD defers parent acknowledgement until child timeout
// [INFO] valid forward parent is receipt-only after recv: true
// [INFO] valid forward parent ack written after child timeout: true
// [EXPECTED] valid forward recv is async; the child timeout resolves the parent ack
//
// [SCENARIO] 4. Valid OP_FORWARD child acknowledgement resolves parent acknowledgement
// [INFO] valid forward parent is receipt-only after recv: true
// [INFO] valid forward parent ack written after child ack: true
// [INFO] valid forward parent remains ack written: true
// [EXPECTED] valid forward child ack resolves the deferred parent ack
//
// [SCENARIO] 5. Multi-hop OP_FORWARD emits a continuation child packet
// [INFO] multi-hop parent is receipt-only after recv: true
// [INFO] multi-hop child packet committed: true
// [INFO] multi-hop child opcode is OP_FORWARD: true
// [INFO] multi-hop child salt is derived: true
// [INFO] multi-hop child source channel is expected: true
// [INFO] multi-hop child destination channel is expected: true
// [EXPECTED] continuation paths keep forwarding instead of executing the final child
