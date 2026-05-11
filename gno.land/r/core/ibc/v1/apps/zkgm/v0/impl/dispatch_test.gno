package impl

import (
	"testing"

	z "gno.land/p/gnoswap/ibc/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/uassert/v0"
	core "gno.land/r/core/ibc/v1/core"
)

func TestRecvDispatchPanicBecomesUniversalErrorAck(cur realm, t *testing.T) {
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
	packet := core.NewPacket(cross, core.Sequence(1), core.ChannelId(1), core.ChannelId(2), data, core.Timestamp(0))

	res := (&ZkgmV1{}).Recv(packet, address("g1relayer"), nil)

	uassert.True(t, res.Status == core.PacketStatusFailure)
	ack, err := z.DecodeAck(res.Ack)
	uassert.NoError(t, err)
	uassert.True(t, ack.Tag.Eq(u256.NewUint(0)))
	uassert.Equal(t, "UNIVERSAL_ERROR", string(ack.InnerAck))
}

func TestRecvMalformedPacketReturnsFailure(cur realm, t *testing.T) {
	packet := core.NewPacket(cross, core.Sequence(1), core.ChannelId(1), core.ChannelId(2), []byte{0x01}, core.Timestamp(0))

	res := (&ZkgmV1{}).Recv(packet, address("g1relayer"), nil)

	uassert.True(t, res.Status == core.PacketStatusFailure)
	uassert.True(t, len(res.Ack) > 0)
}

func TestAckUnsupportedStubAborts(cur realm, t *testing.T) {
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
	packet := core.NewPacket(cross, core.Sequence(1), core.ChannelId(1), core.ChannelId(2), data, core.Timestamp(0))

	uassert.AbortsContains(t, "forward ack not implemented", func(cur realm) {
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
