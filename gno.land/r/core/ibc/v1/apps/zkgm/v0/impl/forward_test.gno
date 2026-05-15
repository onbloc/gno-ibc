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
	err := (&ZkgmV1{}).verifyForward(core.ChannelId(1), "sender", nil, u256.Zero(), [32]byte{}, z.Forward{
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
		err := (&ZkgmV1{}).verifyForward(core.ChannelId(1), sender, nil, u256.Zero(), [32]byte{}, z.Forward{
			Path:        forwardPath(1, 2),
			Instruction: instr,
		})
		uassert.NoError(t, err)
	}
}

func TestBuildForwardChildPacket(cur realm, t *testing.T) {
	// buildForwardChild now consults core.GetChannel(nextSourceChannel) to fill
	// DestinationChannelId; open a channel under the expected source id first.
	nextSource := openForwardTestChannel(cross, core.ChannelId(99))
	parentSalt := [32]byte{0xA}
	parent := core.Packet{SourceChannelId: core.ChannelId(0), DestinationChannelId: core.ChannelId(1)}

	child, err := buildForwardChild(parent, u256.NewUint(9), parentSalt, z.Forward{
		Path:             forwardPath(1, uint32(nextSource)),
		TimeoutTimestamp: 999,
		Instruction:      batchMustCallInstruction(batchCall("sender", "call")),
	})

	uassert.NoError(t, err)
	uassert.Equal(t, uint32(nextSource), uint32(child.SourceChannelId))

	packet, err := z.DecodeZkgmPacket(child.Data)
	uassert.NoError(t, err)
	uassert.True(t, packet.Salt == z.DeriveForwardSalt(parentSalt))
	uassert.True(t, packet.Path.Eq(forwardPath(9, 1, uint32(nextSource))))
	uassert.Equal(t, z.OP_CALL, packet.Instruction.Opcode)
}

func TestBuildForwardNestedRebuildsContinuation(cur realm, t *testing.T) {
	nextSource := openForwardTestChannel(cross, core.ChannelId(99))
	parent := core.Packet{SourceChannelId: core.ChannelId(0), DestinationChannelId: core.ChannelId(1)}

	child, err := buildForwardChild(parent, u256.NewUint(5), [32]byte{}, z.Forward{
		Path:             forwardPath(1, uint32(nextSource), 3),
		TimeoutTimestamp: 444,
		Instruction:      batchMustCallInstruction(batchCall("sender", "call")),
	})

	uassert.NoError(t, err)
	uassert.Equal(t, uint32(nextSource), uint32(child.SourceChannelId))

	packet, err := z.DecodeZkgmPacket(child.Data)
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
	parent := core.Packet{SourceChannelId: core.ChannelId(9), DestinationChannelId: core.ChannelId(1)}
	forward := z.Forward{
		Path:             forwardPath(1, uint32(channelId)),
		TimeoutTimestamp: 333,
		Instruction:      batchMustCallInstruction(batchCall("sender", "async")),
	}

	res, err := (&ZkgmV1{}).executeForward(parent, u256.NewUint(5), [32]byte{0xC}, forward, false)

	uassert.NoError(t, err)
	uassert.True(t, res.Status == core.PacketStatusAsync)
	uassert.True(t, len(res.Ack) == 0)
	// Reconstruct the deterministic child packet to derive the same InFlightKey
	// executeForward stored under (Union batch-hash identity).
	expectedChild, err := buildForwardChild(parent, u256.NewUint(5), [32]byte{0xC}, forward)
	uassert.NoError(t, err)
	_, ok := zkgm.GetInFlightPacket(zkgm.InFlightKey{PacketHash: core.CommitPacket(expectedChild)})
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
	path := forwardPath(1, 2)
	increaseChannelBalanceV2(cross, core.ChannelId(3), path, order.BaseToken, order.QuoteToken, order.BaseAmount)
	childFailAck, err := z.EncodeAck(z.Ack{Tag: tagAckFailure, InnerAck: []byte("failed")})
	uassert.NoError(t, err)

	err = (&ZkgmV1{}).acknowledgeForward(core.Packet{SourceChannelId: core.ChannelId(3), DestinationChannelId: core.ChannelId(4)}, u256.Zero(), [32]byte{}, z.Forward{
		Path:        path,
		Instruction: batchMustOrderInstruction(order),
	}, z.Ack{Tag: tagAckSuccess, InnerAck: childFailAck})

	uassert.NoError(t, err)

	balance := zkgm.GetChannelBalanceV2(ChannelBalanceKeyV2(core.ChannelId(3), path, order.BaseToken, order.QuoteToken))
	uassert.True(t, balance == nil || balance.IsZero())
	uassert.Equal(t, int64(20), VoucherBalanceOf(string(order.BaseToken), address(sender)))
}

func TestConsumeForwardChildClearsInFlight(cur realm, t *testing.T) {
	packet := core.Packet{SourceChannelId: core.ChannelId(2), DestinationChannelId: core.ChannelId(3)}
	parentPacket := core.Packet{SourceChannelId: core.ChannelId(10), DestinationChannelId: core.ChannelId(11)}
	parent := zkgm.InFlightValue{ParentPacket: parentPacket}
	zkgm.SetInFlightPacket(cross, forwardInFlightKey(packet), parent)

	got, ok := consumeForwardChild(packet, z.DeriveForwardSalt([32]byte{0xB}))

	uassert.True(t, ok)
	uassert.Equal(t, uint32(parent.ParentPacket.DestinationChannelId), uint32(got.ParentPacket.DestinationChannelId))
	uassert.Equal(t, uint32(parent.ParentPacket.SourceChannelId), uint32(got.ParentPacket.SourceChannelId))

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
	portId := []byte(zkgm.ProxyPkgPath())
	if !core.HasApp(portId) {
		core.RegisterApp(cross, portId, zkgm.AsIBCApp())
	}
	clientType := core.ClientType("forward-test")
	if !core.HasClient(clientType) {
		core.RegisterClient(cross, clientType, &forwardTestLightClient{})
	}

	clientId := core.CreateClient(cross, core.MsgCreateClient{
		ClientType: clientType,
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
		PortId:             portId,
		CounterpartyPortId: portId,
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
