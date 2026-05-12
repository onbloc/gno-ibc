package impl

import (
	"testing"

	z "gno.land/p/gnoswap/ibc/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/uassert/v0"
	core "gno.land/r/core/ibc/v1/core"
)

func TestRecvForwardExecuteErrorReturnsFailure(cur realm, t *testing.T) {
	data := mustZkgmPacketBytes(z.Instruction{
		Version: z.INSTR_VERSION_0,
		Opcode:  z.OP_FORWARD,
		Operand: mustForwardBytes(z.Forward{
			Path: u256.Zero(),
			Instruction: z.Instruction{
				Version: z.INSTR_VERSION_0,
				Opcode:  z.OP_CALL,
				Operand: mustCallBytes(z.Call{}),
			},
		}),
	})
	packet := core.Packet{SourceChannelId: core.ChannelId(1), DestinationChannelId: core.ChannelId(2), Data: data}

	res := (&ZkgmV1{}).Recv(packet, address("g1relayer"), nil)

	uassert.True(t, res.Status == core.PacketStatusFailure)
	uassert.Equal(t, "zkgm/v1: forward missing previous destination channel", string(res.Ack))
}

func TestRecvMalformedPacketReturnsFailure(cur realm, t *testing.T) {
	packet := core.Packet{SourceChannelId: core.ChannelId(1), DestinationChannelId: core.ChannelId(2), Data: []byte{0x01}}

	res := (&ZkgmV1{}).Recv(packet, address("g1relayer"), nil)

	uassert.True(t, res.Status == core.PacketStatusFailure)
	uassert.True(t, len(res.Ack) > 0)
}

func TestAckUnsupportedOpcodeAborts(cur realm, t *testing.T) {
	data := mustZkgmPacketBytes(z.Instruction{
		Version: z.INSTR_VERSION_0,
		Opcode:  0xFF,
	})
	packet := core.Packet{SourceChannelId: core.ChannelId(1), DestinationChannelId: core.ChannelId(2), Data: data}

	uassert.AbortsContains(t, "unsupported opcode", func(cur realm) {
		(&ZkgmV1{}).Ack(packet, nil, address("g1relayer"))
	})
}

func mustZkgmPacketBytes(instr z.Instruction) []byte {
	out, err := z.EncodeZkgmPacket(z.ZkgmPacket{
		Salt:        [32]byte{},
		Path:        u256.Zero(),
		Instruction: instr,
	})
	if err != nil {
		panic(err)
	}
	return out
}

func mustCallBytes(call z.Call) []byte {
	out, err := z.EncodeCall(call)
	if err != nil {
		panic(err)
	}
	return out
}

func mustForwardBytes(forward z.Forward) []byte {
	out, err := z.EncodeForward(forward)
	if err != nil {
		panic(err)
	}
	return out
}
