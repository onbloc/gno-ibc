package impl

import (
	"errors"

	z "gno.land/p/gnoswap/ibc/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
	core "gno.land/r/core/ibc/v1/core"
)

func (v *ZkgmV1) dispatchVerify(channelId core.ChannelId, salt [32]byte, instr z.Instruction) error {
	return errors.New("zkgm/v1: dispatch verify not implemented")
}

func (v *ZkgmV1) dispatchExecute(packet core.Packet, path *u256.Uint, salt [32]byte, instr z.Instruction, intent bool) (core.RecvPacketResult, error) {
	return core.NewRecvPacketResult(cross, core.PacketStatusUnknown, nil), errors.New("zkgm/v1: dispatch execute not implemented")
}

func (v *ZkgmV1) dispatchAck(packet core.Packet, path *u256.Uint, salt [32]byte, instr z.Instruction, ack core.Bytes) error {
	return errors.New("zkgm/v1: dispatch ack not implemented")
}

func (v *ZkgmV1) dispatchTimeout(packet core.Packet, path *u256.Uint, salt [32]byte, instr z.Instruction) error {
	return errors.New("zkgm/v1: dispatch timeout not implemented")
}
