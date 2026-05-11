package impl

import (
	"testing"

	z "gno.land/p/gnoswap/ibc/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/uassert/v0"
	core "gno.land/r/core/ibc/v1/core"
	zkgm "gno.land/r/gnoswap/ibc/v1/apps/zkgm"
)

func TestVerifyForwardRejectsNestedForward(cur realm, t *testing.T) {
	err := (&ZkgmV1{}).verifyForward(core.ChannelId(1), "sender", nil, [32]byte{}, z.Forward{
		Path: forwardPath(1, 2),
		Instruction: z.Instruction{
			Version: z.INSTR_VERSION_0,
			Opcode:  z.OP_FORWARD,
			Operand: mustForwardBytes(z.Forward{Path: forwardPath(1, 2)}),
		},
	})

	uassert.ErrorContains(t, err, "invalid forward instruction")
}

func TestVerifyForwardPassesAllowedChildren(cur realm, t *testing.T) {
	resetTokenOrderTest()

	sender := testAddress("forward-sender")
	baseToken := "ibc/v1-forward"
	uassert.NoError(t, mintVoucher(cross, baseToken, baseToken, [32]byte{}, sender, u256.NewUint(30)))
	order := z.TokenOrderV2{
		Sender:      []byte(sender),
		BaseToken:   []byte(baseToken),
		BaseAmount:  u256.NewUint(10),
		QuoteToken:  []byte("quote"),
		QuoteAmount: u256.NewUint(10),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}
	batchBytes, err := z.EncodeBatch(z.Batch{Instructions: []z.Instruction{
		batchMustCallInstruction(batchCall(sender, "")),
	}})
	uassert.NoError(t, err)

	cases := []z.Instruction{
		batchMustCallInstruction(batchCall(sender, "")),
		batchMustOrderInstruction(order),
		{Version: z.INSTR_VERSION_0, Opcode: z.OP_BATCH, Operand: batchBytes},
	}
	for _, instr := range cases {
		err := (&ZkgmV1{}).verifyForward(core.ChannelId(1), sender, nil, [32]byte{}, z.Forward{
			Path:        forwardPath(1, 2),
			Instruction: instr,
		})
		uassert.NoError(t, err)
	}
}

func TestBuildForwardChildPacket(cur realm, t *testing.T) {
	parentSalt := [32]byte{0xA}
	parent := core.NewPacket(cross, core.Sequence(7), core.ChannelId(0), core.ChannelId(1), nil, core.Timestamp(0))

	msg, err := buildForwardChild(parent, u256.NewUint(9), parentSalt, z.Forward{
		Path:             forwardPath(1, 2),
		TimeoutTimestamp: 999,
		Instruction:      batchMustCallInstruction(batchCall("sender", "call")),
	})

	uassert.NoError(t, err)
	uassert.Equal(t, uint32(2), uint32(msg.SourceChannelId))

	packet, err := z.DecodeZkgmPacket(msg.Data)
	uassert.NoError(t, err)
	uassert.True(t, packet.Salt == z.DeriveForwardSalt(parentSalt))
	uassert.True(t, packet.Path.Eq(forwardPath(9, 1, 2)))
	uassert.Equal(t, z.OP_CALL, packet.Instruction.Opcode)
}

func TestBuildForwardNestedRebuildsContinuation(cur realm, t *testing.T) {
	parent := core.NewPacket(cross, core.Sequence(7), core.ChannelId(0), core.ChannelId(1), nil, core.Timestamp(0))

	msg, err := buildForwardChild(parent, u256.NewUint(5), [32]byte{}, z.Forward{
		Path:             forwardPath(1, 2, 3),
		TimeoutTimestamp: 444,
		Instruction:      batchMustCallInstruction(batchCall("sender", "call")),
	})

	uassert.NoError(t, err)
	uassert.Equal(t, uint32(2), uint32(msg.SourceChannelId))

	packet, err := z.DecodeZkgmPacket(msg.Data)
	uassert.NoError(t, err)
	uassert.Equal(t, z.OP_FORWARD, packet.Instruction.Opcode)

	nextForward, err := z.DecodeForward(packet.Instruction.Operand)
	uassert.NoError(t, err)
	uassert.True(t, nextForward.Path.Eq(u256.NewUint(3)))
	uassert.Equal(t, uint64(444), nextForward.TimeoutTimestamp)
	uassert.Equal(t, z.OP_CALL, nextForward.Instruction.Opcode)
}

func TestExecuteForwardIntentReturnsOnlyMaker(cur realm, t *testing.T) {
	res, err := (&ZkgmV1{}).executeForward(core.Packet{}, u256.Zero(), [32]byte{}, z.Forward{
		Path:        forwardPath(1, 2),
		Instruction: batchMustCallInstruction(batchCall("sender", "")),
	}, true)

	uassert.NoError(t, err)
	uassert.True(t, res.Status == core.PacketStatusSuccess)
	uassert.True(t, equalBytes(z.ACK_ERR_ONLY_MAKER, res.Ack))
}

func TestExecuteForwardAsyncDefersAckAndTracksChild(cur realm, t *testing.T) {
	channelId := openForwardTestChannel(cross, core.ChannelId(12))
	parent := core.NewPacket(cross, core.Sequence(7), core.ChannelId(9), core.ChannelId(1), nil, core.Timestamp(0))

	res, err := (&ZkgmV1{}).executeForward(parent, u256.NewUint(5), [32]byte{0xC}, z.Forward{
		Path:             forwardPath(1, uint32(channelId)),
		TimeoutTimestamp: 333,
		Instruction:      batchMustCallInstruction(batchCall("sender", "async")),
	}, false)

	uassert.NoError(t, err)
	uassert.True(t, res.Status == core.PacketStatusAsync)
	uassert.True(t, len(res.Ack) == 0)
	_, ok := zkgm.GetInFlightPacket(zkgm.InFlightKey{
		SourceChannelId:      channelId,
		DestinationChannelId: core.ChannelId(12),
		Sequence:             core.Sequence(0),
	})
	uassert.True(t, ok)
}

func TestAcknowledgeForwardDispatchesToInnerInstruction(cur realm, t *testing.T) {
	err := (&ZkgmV1{}).acknowledgeForward(core.Packet{}, u256.Zero(), [32]byte{}, z.Forward{
		Path:        forwardPath(1, 2),
		Instruction: batchMustCallInstruction(batchCall("sender", "calldata")),
	}, z.Ack{Tag: tagAckSuccess, InnerAck: []byte{}})

	uassert.NoError(t, err)
}

func TestAcknowledgeForwardWithTokenOrderChildRefundsOnFailure(cur realm, t *testing.T) {
	resetTokenOrderTest()

	sender := testAddress("forward-refund")
	order := z.TokenOrderV2{
		Sender:      []byte(sender),
		BaseToken:   []byte("ibc/v1-forward-refund"),
		BaseAmount:  u256.NewUint(20),
		QuoteToken:  []byte("quote"),
		QuoteAmount: u256.NewUint(20),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}
	path := u256.NewUint(7)
	increaseChannelBalanceV2(cross, core.ChannelId(3), path, order.BaseToken, order.QuoteToken, order.BaseAmount)
	childFailAck, err := z.EncodeAck(z.Ack{Tag: tagAckFailure, InnerAck: []byte("failed")})
	uassert.NoError(t, err)

	err = (&ZkgmV1{}).acknowledgeForward(core.NewPacket(cross, core.Sequence(1), core.ChannelId(3), core.ChannelId(4), nil, core.Timestamp(0)), path, [32]byte{}, z.Forward{
		Path:        forwardPath(1, 2),
		Instruction: batchMustOrderInstruction(order),
	}, z.Ack{Tag: tagAckSuccess, InnerAck: childFailAck})

	uassert.NoError(t, err)

	balance := zkgm.GetChannelBalanceV2(ChannelBalanceKeyV2(core.ChannelId(3), path, order.BaseToken, order.QuoteToken))
	uassert.True(t, balance == nil || balance.IsZero())
	uassert.Equal(t, int64(20), VoucherBalanceOf(string(order.BaseToken), address(sender)))
}

func TestConsumeForwardChildClearsInFlight(cur realm, t *testing.T) {
	packet := core.NewPacket(cross, core.Sequence(21), core.ChannelId(2), core.ChannelId(3), nil, core.Timestamp(0))
	parent := zkgm.InFlightValue{
		ParentSourceChannelId:      core.ChannelId(10),
		ParentDestinationChannelId: core.ChannelId(11),
		ParentSequence:             core.Sequence(12),
	}
	zkgm.SetInFlightPacket(cross, forwardInFlightKey(packet), parent)

	got, ok := consumeForwardChild(packet, z.DeriveForwardSalt([32]byte{0xB}))

	uassert.True(t, ok)
	uassert.Equal(t, uint32(parent.ParentDestinationChannelId), uint32(got.ParentDestinationChannelId))
	uassert.Equal(t, uint64(parent.ParentSequence), uint64(got.ParentSequence))

	_, ok = zkgm.GetInFlightPacket(forwardInFlightKey(packet))
	uassert.False(t, ok)
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

type forwardTestLightClient struct{}

func (c *forwardTestLightClient) CreateClient(_ realm, clientId core.ClientId, clientStateBytes, consensusStateBytes []byte) string {
	return "forward-counterparty"
}

func (c *forwardTestLightClient) UpdateClient(_ realm, clientId core.ClientId, clientMessage []byte) core.ConsensusStateUpdate {
	return core.ConsensusStateUpdate{}
}

func (c *forwardTestLightClient) Misbehaviour(_ realm, clientId core.ClientId, clientMessage []byte) []byte {
	return nil
}

func (c *forwardTestLightClient) VerifyMembership(clientId core.ClientId, height core.Height, proof []byte, key []byte, value []byte) {
}

func (c *forwardTestLightClient) VerifyNonMembership(clientId core.ClientId, height core.Height, proof []byte, key []byte) {
}

func (c *forwardTestLightClient) GetTimestamp(clientId core.ClientId, height core.Height) core.Timestamp {
	return core.Timestamp(1)
}

func (c *forwardTestLightClient) GetLatestHeight(clientId core.ClientId) core.Height {
	return core.Height(1)
}

func (c *forwardTestLightClient) GetStatus(clientId core.ClientId) core.Status {
	return core.StatusActive
}

func openForwardTestChannel(cur realm, counterpartyChannelId core.ChannelId) core.ChannelId {
	zkgm.UpdateImpl(cross, zkgm.UpdateRequest{Impl: &ZkgmV1{}})
	core.RegisterApp(cross, zkgm.ProxyAddress(), zkgm.AsIBCApp())
	core.RegisterClient(cross, core.ClientType("forward-test"), &forwardTestLightClient{})

	clientId := core.CreateClient(cross, core.MsgCreateClient{
		ClientType:          core.ClientType("forward-test"),
		ClientStateBytes:    core.NewBytes(cross, nil),
		ConsensusStateBytes: core.NewBytes(cross, nil),
	})
	connectionId := core.ConnectionOpenInit(cross, core.MsgConnectionOpenInit{
		ClientId:             clientId,
		CounterpartyClientId: core.ClientId(99),
	})
	core.ConnectionOpenAck(cross, core.MsgConnectionOpenAck{
		ConnectionId:             connectionId,
		CounterpartyConnectionId: core.ConnectionId(77),
	})

	channelId := core.ChannelOpenInit(cross, core.MsgChannelOpenInit{
		PortId:             zkgm.ProxyAddress(),
		CounterpartyPortId: zkgm.ProxyAddress(),
		ConnectionId:       connectionId,
		Version:            zkgm.Version,
	})
	core.ChannelOpenAck(cross, core.MsgChannelOpenAck{
		ChannelId:             channelId,
		CounterpartyVersion:   zkgm.Version,
		CounterpartyChannelId: counterpartyChannelId,
	})
	return channelId
}
