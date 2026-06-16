package e2e

import (
	z "gno.land/p/onbloc/ibc/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
	core "gno.land/r/onbloc/ibc/union/core"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
)

var Relayer = address("g1relayer")

func tagAckSuccessU256() *u256.Uint    { return new(u256.Uint).SetBytes(z.TAG_ACK_SUCCESS[:]) }
func fillTypeProtocolU256() *u256.Uint { return new(u256.Uint).SetBytes(z.FILL_TYPE_PROTOCOL[:]) }

type ChannelPair struct {
	ClientId     core.ClientId
	ConnectionId core.ConnectionId
	Source       core.ChannelId
	Destination  core.ChannelId
}

// NewChannelPair allocates a ChannelPair in this realm so cross-realm callers
// (e.g. the impl test suite) can build one without tripping the Phase 3
// allocation guard.
func NewChannelPair(cur realm, clientId core.ClientId, connectionId core.ConnectionId, source, destination core.ChannelId) ChannelPair {
	return ChannelPair{ClientId: clientId, ConnectionId: connectionId, Source: source, Destination: destination}
}

func RegisterMockLightClient(cur realm) {
	if !core.HasClient(MockClientType) {
		core.RegisterClient(cross(cur), MockClientType, &MockLightClient{})
	}
}

func CreateMockClient(cur realm) core.ClientId {
	return core.CreateClient(cross(cur), core.NewMsgCreateClient(cross(cur), MockClientType, nil, nil))
}

func OpenE2EChannel(cur realm, counterpartyChannelId core.ChannelId) core.ChannelId {
	clientId := CreateMockClient(cross(cur))
	connectionId := openConnection(cur, clientId)
	return openChannel(cur, connectionId, counterpartyChannelId)
}

func OpenE2EChannelPair(cur realm) ChannelPair {
	clientId := CreateMockClient(cross(cur))
	connectionId := openConnection(cur, clientId)

	source := openChannel(cur, connectionId, core.ChannelId(2))
	destination := openChannel(cur, connectionId, source)
	return ChannelPair{
		ClientId:     clientId,
		ConnectionId: connectionId,
		Source:       source,
		Destination:  destination,
	}
}

func openConnection(cur realm, clientId core.ClientId) core.ConnectionId {
	connectionId := core.ConnectionOpenInit(cross(cur), core.NewMsgConnectionOpenInit(cross(cur), clientId, core.ClientId(99)))
	core.ConnectionOpenAck(cross(cur), core.NewMsgConnectionOpenAck(cross(cur), connectionId, core.ConnectionId(77), nil, core.Height(1)))
	return connectionId
}

func openChannel(cur realm, connectionId core.ConnectionId, counterpartyChannelId core.ChannelId) core.ChannelId {
	portId := []byte(zkgm.ProxyPkgPath())
	channelId := core.ChannelOpenInit(cross(cur), core.NewMsgChannelOpenInit(cross(cur), portId, portId, connectionId, zkgm.Version))
	core.ChannelOpenAck(cross(cur), core.NewMsgChannelOpenAck(cross(cur), channelId, zkgm.Version, counterpartyChannelId, nil, core.Height(1)))
	return channelId
}

func BatchSend(cur realm, packet core.Packet) core.H256 {
	return zkgm.BatchSend(cross(cur), core.NewMsgBatchSend(cross(cur), []core.Packet{packet}))
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

func MustForwardInstruction(cur realm, forward z.Forward) z.Instruction {
	forwardBytes, err := z.EncodeForward(forward)
	if err != nil {
		panic(err)
	}
	return z.Instruction{
		Version: z.INSTR_VERSION_0,
		Opcode:  z.OP_FORWARD,
		Operand: forwardBytes,
	}
}

func ForwardPath(cur realm, channels ...uint32) *u256.Uint {
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

func MustForwardChildPacket(cur realm, packet core.Packet, path *u256.Uint, parentSalt [32]byte, forward z.Forward) core.Packet {
	forwardPath := mustCloneUint(forward.Path)
	tailPath, prevDestChannel := z.DequeueChannelFromPath(forwardPath)
	if prevDestChannel == 0 {
		panic("zkgm/e2e: forward missing previous destination channel")
	}
	continuationPath, nextSourceChannel := z.DequeueChannelFromPath(tailPath)
	if nextSourceChannel == 0 {
		panic("zkgm/e2e: forward missing next source channel")
	}
	if packet.DestinationChannelId != core.ChannelId(prevDestChannel) {
		panic("zkgm/e2e: forward previous-destination mismatch")
	}

	nextInstruction := forward.Instruction
	if !continuationPath.IsZero() {
		nextForward := z.Forward{
			Path:             continuationPath,
			TimeoutHeight:    0,
			TimeoutTimestamp: forward.TimeoutTimestamp,
			Instruction:      forward.Instruction,
		}
		nextInstruction = MustForwardInstruction(cross(cur), nextForward)
	}

	intermediate, err := z.UpdateChannelPath(path, prevDestChannel)
	if err != nil {
		panic(err)
	}
	nextPath, err := z.UpdateChannelPath(intermediate, nextSourceChannel)
	if err != nil {
		panic(err)
	}

	childBytes, err := z.EncodeZkgmPacket(z.ZkgmPacket{
		Salt:        z.DeriveForwardSalt(parentSalt),
		Path:        nextPath,
		Instruction: nextInstruction,
	})
	if err != nil {
		panic(err)
	}

	sourceChannelId := core.ChannelId(nextSourceChannel)
	sourceChannel := core.GetChannel(sourceChannelId)
	return core.NewPacket(cross(cur), sourceChannelId, sourceChannel.CounterpartyChannelId, childBytes, 0, core.Timestamp(forward.TimeoutTimestamp))
}

func mustCloneUint(in *u256.Uint) *u256.Uint {
	out, err := u256.FromDecimal(in.Dec())
	if err != nil {
		panic(err)
	}
	return out
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

func MustTokenMetadata(cur realm, implementation string, ti z.TokenInitializer) []byte {
	initBytes, err := z.EncodeTokenInitializer(ti)
	if err != nil {
		panic(err)
	}
	meta, err := z.EncodeTokenMetadata(z.TokenMetadata{
		Implementation: []byte(implementation),
		Initializer:    initBytes,
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
		FillType: fillTypeProtocolU256(),
	})
	if err != nil {
		panic(err)
	}
	return bz
}

func MustSuccessAck(cur realm, inner []byte) []byte {
	return MustAck(cross(cur), tagAckSuccessU256(), inner)
}

func MustSuccessAckBytes(cur realm, inner []byte) []byte {
	ack, err := z.EncodeAck(z.Ack{Tag: tagAckSuccessU256(), InnerAck: inner})
	if err != nil {
		panic(err)
	}
	return ack
}

func MustCallAck(cur realm) []byte {
	return MustSuccessAckBytes(cross(cur), []byte{})
}

func MustBatchAck(cur realm, childAcks [][]byte) []byte {
	batchAck, err := z.EncodeBatchAck(z.BatchAck{Acknowledgements: childAcks})
	if err != nil {
		panic(err)
	}
	return MustSuccessAckBytes(cross(cur), batchAck)
}
