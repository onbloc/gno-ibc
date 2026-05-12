package e2e

import (
	z "gno.land/p/gnoswap/ibc/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
	core "gno.land/r/core/ibc/v1/core"
	zkgm "gno.land/r/gnoswap/ibc/v1/apps/zkgm"
)

var (
	Relayer = address("g1relayer")

	tagAckSuccessU256    = new(u256.Uint).SetBytes(z.TAG_ACK_SUCCESS[:])
	fillTypeProtocolU256 = new(u256.Uint).SetBytes(z.FILL_TYPE_PROTOCOL[:])
)

type ChannelPair struct {
	ClientId     core.ClientId
	ConnectionId core.ConnectionId
	Source       core.ChannelId
	Destination  core.ChannelId
}

func RegisterMockLightClient(cur realm) {
	if !core.HasClient(MockClientType) {
		core.RegisterClient(cross, MockClientType, &MockLightClient{})
	}
}

func CreateMockClient(cur realm) core.ClientId {
	return core.CreateClient(cross, core.MsgCreateClient{
		ClientType: MockClientType,
	})
}

func OpenE2EChannel(cur realm, counterpartyChannelId core.ChannelId) core.ChannelId {
	clientId := CreateMockClient(cross)
	connectionId := openConnection(clientId)
	return openChannel(connectionId, counterpartyChannelId)
}

func OpenE2EChannelPair(cur realm) ChannelPair {
	clientId := CreateMockClient(cross)
	connectionId := openConnection(clientId)

	source := openChannel(connectionId, core.ChannelId(2))
	destination := openChannel(connectionId, source)
	return ChannelPair{
		ClientId:     clientId,
		ConnectionId: connectionId,
		Source:       source,
		Destination:  destination,
	}
}

func openConnection(clientId core.ClientId) core.ConnectionId {
	connectionId := core.ConnectionOpenInit(cross, core.MsgConnectionOpenInit{
		ClientId:             clientId,
		CounterpartyClientId: core.ClientId(99),
	})
	core.ConnectionOpenAck(cross, core.MsgConnectionOpenAck{
		ConnectionId:             connectionId,
		CounterpartyConnectionId: core.ConnectionId(77),
		ProofHeight:              core.Height(1),
	})
	return connectionId
}

func openChannel(connectionId core.ConnectionId, counterpartyChannelId core.ChannelId) core.ChannelId {
	portId := []byte(zkgm.ProxyAddress())
	channelId := core.ChannelOpenInit(cross, core.MsgChannelOpenInit{
		PortId:             portId,
		CounterpartyPortId: portId,
		ConnectionId:       connectionId,
		Version:            zkgm.Version,
	})
	core.ChannelOpenAck(cross, core.MsgChannelOpenAck{
		ChannelId:             channelId,
		CounterpartyVersion:   zkgm.Version,
		CounterpartyChannelId: counterpartyChannelId,
		ProofHeight:           core.Height(1),
	})
	return channelId
}

func MustTokenOrderInstruction(cur realm, order z.TokenOrderV2) z.Instruction {
	orderBytes, err := z.EncodeTokenOrderV2(order)
	if err != nil {
		panic(err)
	}
	return z.Instruction{
		Version: z.INSTR_VERSION_2,
		Opcode:  z.OP_TOKEN_ORDER,
		Operand: orderBytes,
	}
}

func MustCallInstruction(cur realm, call z.Call) z.Instruction {
	callBytes, err := z.EncodeCall(call)
	if err != nil {
		panic(err)
	}
	return z.Instruction{
		Version: z.INSTR_VERSION_0,
		Opcode:  z.OP_CALL,
		Operand: callBytes,
	}
}

func MustBatchInstruction(cur realm, batch z.Batch) z.Instruction {
	batchBytes, err := z.EncodeBatch(batch)
	if err != nil {
		panic(err)
	}
	return z.Instruction{
		Version: z.INSTR_VERSION_0,
		Opcode:  z.OP_BATCH,
		Operand: batchBytes,
	}
}

func MustPacketData(cur realm, instr z.Instruction) []byte {
	packetBytes, err := z.EncodeZkgmPacket(z.ZkgmPacket{
		Path:        u256.Zero(),
		Instruction: instr,
	})
	if err != nil {
		panic(err)
	}
	return packetBytes
}

func MustTokenMetadata(cur realm, implementation string, initializer string) []byte {
	meta, err := z.EncodeTokenMetadata(z.TokenMetadata{
		Implementation: []byte(implementation),
		Initializer:    []byte(initializer),
	})
	if err != nil {
		panic(err)
	}
	return meta
}

func MustAck(cur realm, tag *u256.Uint, inner []byte) []byte {
	ack, err := z.EncodeAck(z.Ack{Tag: tag, InnerAck: inner})
	if err != nil {
		panic(err)
	}
	return ack
}

func MustProtocolTokenOrderAck(cur realm) []byte {
	bz, err := z.EncodeTokenOrderAck(z.TokenOrderAck{
		FillType: fillTypeProtocolU256,
	})
	if err != nil {
		panic(err)
	}
	return bz
}

func MustSuccessAck(cur realm, inner []byte) []byte {
	return MustAck(cross, tagAckSuccessU256, inner)
}

func MustSuccessAckBytes(cur realm, inner []byte) []byte {
	ack, err := z.EncodeAck(z.Ack{Tag: tagAckSuccessU256, InnerAck: inner})
	if err != nil {
		panic(err)
	}
	return ack
}

func MustCallAck(cur realm) []byte {
	return MustSuccessAckBytes(cross, []byte{})
}

func MustBatchAck(cur realm, childAcks [][]byte) []byte {
	batchAck, err := z.EncodeBatchAck(z.BatchAck{Acknowledgements: childAcks})
	if err != nil {
		panic(err)
	}
	return MustSuccessAckBytes(cross, batchAck)
}
