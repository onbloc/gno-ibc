package impl

import (
	"bytes"
	"testing"

	types "gno.land/p/onbloc/ibc/union/types"

	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/uassert/v0"
	z "gno.land/p/onbloc/ibc/union/zkgm"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	core "gno.land/r/onbloc/ibc/union/core"
)

func TestVerifyForwardRejectsNestedForward(cur realm, t *testing.T) {
	err := (&ZkgmV1{}).verifyForward(cur, types.ChannelId(1), "sender", newSentCoinBudget(nil), u256.Zero(), [32]byte{}, z.Forward{
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
	resetTokenOrderTest(cur)

	sender := testAddress("forward-sender")
	baseToken := "ibc/v1-forward"
	uassert.NoError(t, zkgm.MintVoucher(cross(cur), baseToken, baseToken, [32]byte{}, "", "", 0, sender, u256.NewUint(30)))
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
		err := (&ZkgmV1{}).verifyForward(cur, types.ChannelId(1), sender, newSentCoinBudget(nil), u256.Zero(), [32]byte{}, z.Forward{
			Path:             forwardPath(1, 2),
			TimeoutTimestamp: 999,
			Instruction:      instr,
		})
		uassert.NoError(t, err)
	}
}

func TestVerifyForwardRejectsZeroTimeout(cur realm, t *testing.T) {
	err := (&ZkgmV1{}).verifyForward(cur, types.ChannelId(1), "sender", newSentCoinBudget(nil), u256.Zero(), [32]byte{}, z.Forward{
		Path:             forwardPath(1, 2),
		TimeoutTimestamp: 0,
		Instruction:      batchMustCallInstruction(batchCall("sender", "")),
	})

	uassert.True(t, err == errForwardZeroTimeout)
}

func TestVerifyForwardAllowsMaxHopPath(cur realm, t *testing.T) {
	err := (&ZkgmV1{}).verifyForward(cur, types.ChannelId(1), "sender", newSentCoinBudget(nil), u256.Zero(), [32]byte{}, z.Forward{
		Path:             forwardPath(1, 2, 3, 4, 5, 6, 7, 8),
		TimeoutTimestamp: 999,
		Instruction:      batchMustCallInstruction(batchCall("sender", "")),
	})

	uassert.NoError(t, err)
}

func TestBuildForwardChildPacket(cur realm, t *testing.T) {
	// buildForwardChild now consults core.GetChannel(nextSourceChannel) to fill
	// DestinationChannelId; open a channel under the expected source id first.
	nextSource := openForwardTestChannel(cross(cur), types.ChannelId(99))
	parentSalt := [32]byte{0xA}
	parent := core.NewPacket(cross(cur), types.ChannelId(0), types.ChannelId(1), nil, 0)

	child, err := buildForwardChild(cur, parent, u256.NewUint(9), parentSalt, z.Forward{
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

func TestBuildForwardChildRejectsInvalidPath(cur realm, t *testing.T) {
	cases := []struct {
		name    string
		destCh  types.ChannelId
		path    *u256.Uint
		wantErr error
	}{
		{"missing prev dest", types.ChannelId(1), u256.Zero(), errForwardMissingPrevDest},
		{"missing next source", types.ChannelId(5), forwardPath(5), errForwardMissingNextSource},
		{"prev dest mismatch", types.ChannelId(7), forwardPath(5, 99), errForwardPrevDestMismatch},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			parent := core.NewPacket(cross(cur), types.ChannelId(0), tc.destCh, nil, 0)
			_, err := buildForwardChild(cur, parent, u256.Zero(), [32]byte{}, z.Forward{
				Path:             tc.path,
				TimeoutTimestamp: 999,
				Instruction:      batchMustCallInstruction(batchCall("sender", "")),
			})
			uassert.True(t, err == tc.wantErr)
		})
	}
}

func TestBuildForwardChildRejectsZeroTimeout(cur realm, t *testing.T) {
	nextSource := openForwardTestChannel(cross(cur), types.ChannelId(99))
	parent := core.NewPacket(cross(cur), types.ChannelId(0), types.ChannelId(1), nil, 0)

	child, err := buildForwardChild(cur, parent, u256.NewUint(9), [32]byte{0xA}, z.Forward{
		Path:             forwardPath(1, uint32(nextSource)),
		TimeoutTimestamp: 0,
		Instruction:      batchMustCallInstruction(batchCall("sender", "call")),
	})

	uassert.Error(t, err)
	uassert.True(t, err == errForwardZeroTimeout)
	uassert.Equal(t, uint32(0), uint32(child.SourceChannelId))
	uassert.Equal(t, uint32(0), uint32(child.DestinationChannelId))
	uassert.True(t, len(child.Data) == 0)
	uassert.True(t, child.TimeoutHeight == 0)
	uassert.True(t, child.TimeoutTimestamp == types.Timestamp(0))
}

func TestBuildForwardNestedRebuildsContinuation(cur realm, t *testing.T) {
	nextSource := openForwardTestChannel(cross(cur), types.ChannelId(99))
	parent := core.NewPacket(cross(cur), types.ChannelId(0), types.ChannelId(1), nil, 0)

	child, err := buildForwardChild(cur, parent, u256.NewUint(5), [32]byte{}, z.Forward{
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
	res, err := (&ZkgmV1{}).executeForward(cur, core.NewPacket(cross(cur), 0, 0, nil, 0), u256.Zero(), [32]byte{}, z.Forward{
		Path:        forwardPath(1, 2),
		Instruction: batchMustCallInstruction(batchCall("sender", "")),
	}, true)

	uassert.NoError(t, err)
	uassert.True(t, res.Status == types.PacketStatusSuccess)
	uassert.True(t, bytes.Equal(z.ACK_ERR_ONLY_MAKER, res.Acknowledgement))
}

func TestIntentRecvOnlyMakerForwardAborts(cur realm, t *testing.T) {
	data := mustZkgmPacketBytes(z.Instruction{
		Version: z.INSTR_VERSION_0,
		Opcode:  z.OP_FORWARD,
		Operand: mustForwardBytes(z.Forward{
			Path:        forwardPath(1, 2),
			Instruction: batchMustCallInstruction(batchCall("sender", "")),
		}),
	})
	packet := core.NewPacket(cross(cur), types.ChannelId(7), types.ChannelId(8), data, 0)

	uassert.AbortsContains(t, cur, "zkgm: only maker", func(cur realm) {
		(&ZkgmV1{}).IntentRecv(cur, packet, address("g1relayer"), nil)
	})
}

func TestExecuteForwardAsyncDefersAckAndTracksChild(cur realm, t *testing.T) {
	channelId := openForwardTestChannel(cross(cur), types.ChannelId(12))
	parent := core.NewPacket(cross(cur), types.ChannelId(9), types.ChannelId(1), nil, 0)
	forward := z.Forward{
		Path:             forwardPath(1, uint32(channelId)),
		TimeoutTimestamp: 333,
		Instruction:      batchMustCallInstruction(batchCall("sender", "async")),
	}

	res, err := (&ZkgmV1{}).executeForward(cur, parent, u256.NewUint(5), [32]byte{0xC}, forward, false)

	uassert.NoError(t, err)
	uassert.True(t, res.Status == types.PacketStatusAsync)
	uassert.True(t, len(res.Acknowledgement) == 0)
	// Reconstruct the deterministic child packet to derive the same InFlightKey
	// executeForward stored under (Union batch-hash identity).
	expectedChild, err := buildForwardChild(cur, parent, u256.NewUint(5), [32]byte{0xC}, forward)
	uassert.NoError(t, err)
	_, ok := zkgm.GetInFlightPacket(zkgm.NewInFlightKey(cross(cur), types.MustCommit(types.CommitPacket(expectedChild))))
	uassert.True(t, ok)
}

func TestExecuteForwardZeroTimeoutFailsCleanly(cur realm, t *testing.T) {
	channelId := openForwardTestChannel(cross(cur), types.ChannelId(12))
	parent := core.NewPacket(cross(cur), types.ChannelId(9), types.ChannelId(1), nil, 0)
	forward := z.Forward{
		Path:             forwardPath(1, uint32(channelId)),
		TimeoutTimestamp: 0,
		Instruction:      batchMustCallInstruction(batchCall("sender", "async")),
	}

	res, err := (&ZkgmV1{}).executeForward(cur, parent, u256.NewUint(5), [32]byte{0xC}, forward, false)

	uassert.Error(t, err)
	uassert.True(t, err == errForwardZeroTimeout)
	uassert.True(t, res.Status == types.PacketStatusUnknown)
	child := core.NewPacket(cross(cur), types.ChannelId(channelId), types.ChannelId(12), nil, 0)
	_, ok := zkgm.GetInFlightPacket(zkgm.NewInFlightKey(cross(cur), types.MustCommit(types.CommitPacket(child))))
	uassert.False(t, ok)
	uassert.False(t, core.HasPacketCommitment(cross(cur), child))
}

func TestExecuteForwardThroughCoreFrameAuthorizesCoreRealm(cur realm, t *testing.T) {
	// openForwardTestChannel installs the impl from this package, so this
	// wiring smoke authorizes via implPath == impl. Scenario filetests cover
	// the allowedImpls branch for the same forward receive frame.
	parentChannel := openForwardTestChannel(cross(cur), types.ChannelId(101))
	childSource := openForwardTestChannel(cross(cur), types.ChannelId(102))
	zkgm.UpdateImpl(cross(cur), zkgm.NewUpdateRequest(cross(cur), nil, []string{
		"gno.land/r/onbloc/ibc/union/core",
		"gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1",
	}))

	forward := z.Forward{
		Path:             forwardPath(uint32(parentChannel), uint32(childSource)),
		TimeoutTimestamp: 999,
		Instruction:      batchMustCallInstruction(batchCall("sender", "core-frame")),
	}
	data := mustZkgmPacketBytes(z.Instruction{
		Version: z.INSTR_VERSION_0,
		Opcode:  z.OP_FORWARD,
		Operand: mustForwardBytes(forward),
	})
	packet := core.NewPacket(cross(cur), types.ChannelId(1), parentChannel, data, types.Timestamp(0))

	core.PacketRecv(cross(cur), types.NewMsgPacketRecv([]types.Packet{packet}, nil, nil, 1))

	expectedChild, err := buildForwardChild(cur, packet, u256.Zero(), [32]byte{}, forward)
	uassert.NoError(t, err)
	_, ok := zkgm.GetInFlightPacket(zkgm.NewInFlightKey(cross(cur), types.MustCommit(types.CommitPacket(expectedChild))))
	uassert.True(t, ok)
	uassert.False(t, core.HasAcknowledgement(cross(cur), packet))
}

func TestAcknowledgeForwardDispatchesToInnerInstruction(cur realm, t *testing.T) {
	err := (&ZkgmV1{}).acknowledgeForward(cur, core.NewPacket(cross(cur), 0, 0, nil, 0), u256.Zero(), [32]byte{}, z.Forward{
		Path:        forwardPath(1, 2),
		Instruction: batchMustCallInstruction(batchCall("sender", "calldata")),
	}, z.Ack{Tag: tagAckSuccess(), InnerAck: []byte{}})

	uassert.NoError(t, err)
}

func TestAcknowledgeForwardWithTokenOrderChildRefundsOnFailure(cur realm, t *testing.T) {
	resetTokenOrderTest(cur)

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
	increaseChannelBalanceV2(cross(cur), types.ChannelId(3), path, order.BaseToken, order.QuoteToken, order.BaseAmount)
	childFailAck, err := z.EncodeAck(z.Ack{Tag: tagAckFailure(), InnerAck: []byte("failed")})
	uassert.NoError(t, err)

	err = (&ZkgmV1{}).acknowledgeForward(cur, core.NewPacket(cross(cur), types.ChannelId(3), types.ChannelId(4), nil, 0), u256.Zero(), [32]byte{}, z.Forward{
		Path:        path,
		Instruction: batchMustOrderInstruction(order),
	}, z.Ack{Tag: tagAckSuccess(), InnerAck: childFailAck})

	uassert.NoError(t, err)

	balance := zkgm.GetChannelBalanceV2(ChannelBalanceKeyV2(types.ChannelId(3), path, order.BaseToken, order.QuoteToken))
	uassert.True(t, balance == nil || balance.IsZero())
	uassert.Equal(t, int64(20), VoucherBalanceOf(string(order.BaseToken), address(sender)))
}

func TestConsumeForwardChildClearsInFlight(cur realm, t *testing.T) {
	packet := core.NewPacket(cross(cur), types.ChannelId(2), types.ChannelId(3), nil, 0)
	parentPacket := core.NewPacket(cross(cur), types.ChannelId(10), types.ChannelId(11), nil, 0)
	parent := zkgm.NewInFlightValue(cross(cur), parentPacket)
	zkgm.SetInFlightPacket(cross(cur), forwardInFlightKey(cur, packet), parent)

	got, ok := consumeForwardChild(cur, packet, z.DeriveForwardSalt([32]byte{0xB}))

	uassert.True(t, ok)
	uassert.Equal(t, uint32(parent.ParentPacket.DestinationChannelId), uint32(got.ParentPacket.DestinationChannelId))
	uassert.Equal(t, uint32(parent.ParentPacket.SourceChannelId), uint32(got.ParentPacket.SourceChannelId))

	_, ok = zkgm.GetInFlightPacket(forwardInFlightKey(cur, packet))
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

func (c *forwardTestLightClient) CreateClient(_ realm, clientId types.ClientId, clientStateBytes, consensusStateBytes []byte) string {
	return "forward-counterparty"
}

func (c *forwardTestLightClient) UpdateClient(_ realm, clientId types.ClientId, clientMessage []byte) types.ConsensusStateUpdate {
	return types.ConsensusStateUpdate{}
}

func (c *forwardTestLightClient) VerifyMembership(clientId types.ClientId, height types.Height, proof []byte, key []byte, value []byte) {
}

func (c *forwardTestLightClient) VerifyNonMembership(clientId types.ClientId, height types.Height, proof []byte, key []byte) {
}

func (c *forwardTestLightClient) GetTimestamp(clientId types.ClientId, height types.Height) types.Timestamp {
	return types.Timestamp(1)
}

func (c *forwardTestLightClient) GetLatestHeight(clientId types.ClientId) types.Height {
	return types.NewHeight(1)
}

func (c *forwardTestLightClient) GetStatus(clientId types.ClientId) types.Status {
	return types.StatusActive
}

func openForwardTestChannel(cur realm, counterpartyChannelId types.ChannelId) types.ChannelId {
	zkgm.UpdateImpl(cross(cur), zkgm.NewUpdateRequest(cross(cur), &ZkgmV1{}, nil))
	portId := []byte(zkgm.ProxyPkgPath())
	if !core.HasApp(portId) {
		zkgm.RegisterCoreApp(cross(cur))
	}
	clientType := types.ClientType("gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1/forward-test")
	if !core.HasClient(clientType) {
		core.RegisterClient(cross(cur), clientType, &forwardTestLightClient{})
	}

	clientId := core.CreateClient(cross(cur), types.NewMsgCreateClient(clientType, nil, nil))
	connectionId := core.ConnectionOpenInit(cross(cur), types.NewMsgConnectionOpenInit(clientId, types.ClientId(99)))
	core.ConnectionOpenAck(cross(cur), types.NewMsgConnectionOpenAck(connectionId, types.ConnectionId(77), nil, 0))

	channelId := core.ChannelOpenInit(cross(cur), types.NewMsgChannelOpenInit(portId, portId, connectionId, zkgm.Version))
	core.ChannelOpenAck(cross(cur), types.NewMsgChannelOpenAck(channelId, zkgm.Version, counterpartyChannelId, nil, 0))
	return channelId
}
