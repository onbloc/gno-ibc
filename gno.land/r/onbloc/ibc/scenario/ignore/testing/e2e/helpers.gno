package e2e

import (
	stdtesting "testing"

	types "gno.land/p/onbloc/ibc/union/types"

	u256 "gno.land/p/gnoswap/uint256"
	z "gno.land/p/onbloc/ibc/union/zkgm"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	core "gno.land/r/onbloc/ibc/union/core"
)

var Relayer = address("g1relayer")

var (
	testClientSeq     uint32
	testConnectionSeq uint32
)

func nextTestClientId() types.ClientId {
	testClientSeq++
	return types.ClientId(testClientSeq)
}

func nextTestConnectionId() types.ConnectionId {
	testConnectionSeq++
	return types.ConnectionId(testConnectionSeq)
}

func tagAckSuccessU256() *u256.Uint    { return new(u256.Uint).SetBytes(z.TAG_ACK_SUCCESS[:]) }
func fillTypeProtocolU256() *u256.Uint { return new(u256.Uint).SetBytes(z.FILL_TYPE_PROTOCOL[:]) }

type ChannelPair struct {
	ClientId     types.ClientId
	ConnectionId types.ConnectionId
	Source       types.ChannelId
	Destination  types.ChannelId
}

// NewChannelPair allocates a ChannelPair in this realm so cross-realm callers
// (e.g. the impl test suite) can build one without tripping the Phase 3
// allocation guard.
func NewChannelPair(cur realm, clientId types.ClientId, connectionId types.ConnectionId, source, destination types.ChannelId) ChannelPair {
	return ChannelPair{ClientId: clientId, ConnectionId: connectionId, Source: source, Destination: destination}
}

func RegisterMockLightClient(cur realm) {
	if !core.HasClient(MockClientType) {
		core.RegisterClient(cross(cur), MockClientType, MockClientImpl)
	}
}

func CreateMockClient(cur realm) types.ClientId {
	RegisterMockLightClient(cross(cur))

	clientId := nextTestClientId()

	core.CreateClient(cross(cur), types.NewMsgCreateClient(MockClientType, nil, nil))

	return clientId
}

func OpenE2EChannel(cur realm, counterpartyChannelId types.ChannelId) types.ChannelId {
	clientId := CreateMockClient(cross(cur))
	connectionId := openConnection(cur, clientId)

	return openChannel(cur, connectionId, counterpartyChannelId)
}

func OpenE2EChannelPair(cur realm) ChannelPair {
	clientId := CreateMockClient(cross(cur))
	connectionId := openConnection(cur, clientId)

	source := openChannel(cur, connectionId, types.ChannelId(2))
	destination := openChannel(cur, connectionId, source)

	return ChannelPair{
		ClientId:     clientId,
		ConnectionId: connectionId,
		Source:       source,
		Destination:  destination,
	}
}

func openConnection(cur realm, clientId types.ClientId) types.ConnectionId {
	connectionId := nextTestConnectionId()

	core.ConnectionOpenInit(cross(cur), types.NewMsgConnectionOpenInit(clientId, types.ClientId(99)))
	core.ConnectionOpenAck(cross(cur), types.NewMsgConnectionOpenAck(connectionId, types.ConnectionId(77), nil, 1))

	return connectionId
}

// e2eChannelSeq mirrors the core store's monotonic channel-id allocation so the
// helpers can recover the id ChannelOpenInit no longer returns. Every e2e channel
// is created through openChannel, so it stays in lockstep with the store; it
// resets with each filetest's fresh realm.
var e2eChannelSeq uint32

func openChannel(cur realm, connectionId types.ConnectionId, counterpartyChannelId types.ChannelId) types.ChannelId {
	portId := []byte(zkgm.ProxyPkgPath())
	core.ChannelOpenInit(cross(cur), types.NewMsgChannelOpenInit(portId, portId, connectionId, zkgm.Version, "g1msgrelayer"))
	e2eChannelSeq++
	channelId := types.ChannelId(e2eChannelSeq)
	core.ChannelOpenAck(cross(cur), types.NewMsgChannelOpenAck(channelId, zkgm.Version, counterpartyChannelId, nil, 1, "g1msgrelayer"))

	return channelId
}

func BatchSend(cur realm, packet types.Packet) types.H256 {
	stdtesting.SetRealm(stdtesting.NewCodeRealm(zkgm.ProductionImplPath()))
	core.BatchSend(cross(cur), types.NewMsgBatchSend([]types.Packet{packet}))
	stdtesting.SetRealm(stdtesting.NewCodeRealm("gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/e2e"))

	return types.MustCommit(types.CommitPackets([]types.Packet{packet}))
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

func MustForwardChildPacket(cur realm, packet types.Packet, path *u256.Uint, parentSalt [32]byte, forward z.Forward) types.Packet {
	forwardPath := mustCloneUint(forward.Path)

	tailPath, prevDestChannel := z.DequeueChannelFromPath(forwardPath)
	if prevDestChannel == 0 {
		panic("zkgm/e2e: forward missing previous destination channel")
	}

	continuationPath, nextSourceChannel := z.DequeueChannelFromPath(tailPath)
	if nextSourceChannel == 0 {
		panic("zkgm/e2e: forward missing next source channel")
	}

	if packet.DestinationChannelId != types.ChannelId(prevDestChannel) {
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

	sourceChannelId := types.ChannelId(nextSourceChannel)
	sourceChannel, err := core.GetChannel(sourceChannelId)
	if err != nil {
		panic(err)
	}

	return core.NewPacket(sourceChannelId, sourceChannel.CounterpartyChannelId, childBytes, types.Timestamp(forward.TimeoutTimestamp))
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
