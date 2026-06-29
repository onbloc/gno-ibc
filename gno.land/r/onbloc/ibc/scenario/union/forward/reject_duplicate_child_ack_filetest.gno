// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/forward
package forward

// This scenario test proves a forwarded child packet cannot
// resolve its parent acknowledgement twice.

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

	salt := [32]byte{0x05}
	parent := forwardPacket(channelId, salt, forwardPath(uint32(channelId), uint32(channelId)))
	child := forwardedChildPacket(channelId, salt)
	msg := core.NewMsgPacketAcknowledgement([]types.Packet{child}, [][]byte{successAck()}, nil, 1)

	println("[SCENARIO] 2. First child acknowledgement resolves the parent")
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{parent}, [][]byte{nil}, nil, 1))
	core.PacketAcknowledgement(cross(cur), msg)
	ufmt.Printf("[INFO] parent ack written after first child ack: %t\n", ackWritten(parent))
	ufmt.Println("[EXPECTED] first child ack settles the in-flight parent")
	println("")

	println("[SCENARIO] 3. Duplicate child acknowledgement is rejected")
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketAcknowledgement(cross(cur), msg)
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

func ackWritten(packet types.Packet) bool {
	commitment, err := core.GetBatchReceipts(core.CommitPacketHash(packet))
	return err == nil && commitment != types.COMMITMENT_MAGIC
}

// Output:
// [SCENARIO] 1. Bootstrap IBC host and open a zkgm channel
//
// [SCENARIO] 2. First child acknowledgement resolves the parent
// [INFO] parent ack written after first child ack: true
// [EXPECTED] first child ack settles the in-flight parent
//
// [SCENARIO] 3. Duplicate child acknowledgement is rejected

// Error:
// packet already acknowledged
