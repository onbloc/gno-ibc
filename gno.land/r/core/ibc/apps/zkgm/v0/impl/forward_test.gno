package impl

import (
	"testing"

	"gno.land/p/aib/ibc/types"
	z "gno.land/p/gnoswap/ibc/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/uassert/v0"
	zkgm "gno.land/r/gnoswap/ibc/apps/zkgm"
	"gno.land/r/gnoswap/ibc/apps/zkgm/testing/mock"
)

func TestVerifyForwardRejectsNestedForward(cur realm, t *testing.T) {
	forwardBytes, err := z.EncodeForward(z.Forward{Path: forwardPath(1, 2)})
	uassert.NoError(t, err)

	err = (&ZkgmV0{}).verifyForward("client-1", "sender", nil, u256.Zero(), z.Forward{
		Path: forwardPath(1, 2),
		Instruction: z.Instruction{
			Version: z.INSTR_VERSION_0,
			Opcode:  z.OP_FORWARD,
			Operand: forwardBytes,
		},
	})

	uassert.ErrorContains(t, err, "invalid forward instruction")
}

func TestVerifyForwardPassesAllowedChildren(cur realm, t *testing.T) {
	resetImplForTest()
	sender := testAddress("sender")
	baseToken := "ibc/forward"
	uassert.NoError(t, mintVoucher(cross, baseToken, baseToken, [32]byte{}, sender, u256.NewUint(30)))
	order := z.TokenOrderV2{
		Sender:      []byte(sender),
		BaseToken:   []byte(baseToken),
		BaseAmount:  u256.NewUint(10),
		QuoteToken:  []byte("quote"),
		QuoteAmount: u256.NewUint(10),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}
	call := batchCall(sender, "")
	batch := z.Batch{Instructions: []z.Instruction{mustCallInstruction(call)}}
	batchBytes, err := z.EncodeBatch(batch)
	uassert.NoError(t, err)

	cases := []z.Instruction{
		mustCallInstruction(call),
		mustOrderInstruction(order),
		{Version: z.INSTR_VERSION_0, Opcode: z.OP_BATCH, Operand: batchBytes},
	}
	for _, instr := range cases {
		err := (&ZkgmV0{}).verifyForward("client-1", sender, nil, u256.Zero(), z.Forward{
			Path:        forwardPath(1, 2),
			Instruction: instr,
		})
		uassert.NoError(t, err)
	}
}

func TestVerifyForwardAllowsPathHelperMaximum(cur realm, t *testing.T) {
	err := (&ZkgmV0{}).verifyForward("client-1", "sender", nil, u256.Zero(), z.Forward{
		Path:        forwardPath(1, 2, 3, 4, 5, 6, 7),
		Instruction: mustCallInstruction(batchCall("sender", "")),
	})

	uassert.NoError(t, err)
}

func TestBuildForwardChildPacket(cur realm, t *testing.T) {
	parentSalt := [32]byte{0xA}
	payload, hash, nextSourceChannel, err := buildForwardChild(zkgm.RecvRequest{
		SourceClient:      "client-0",
		DestinationClient: "client-1",
		Sequence:          7,
		Payload:           mustForwardPayload(z.Forward{Path: forwardPath(1, 2)}),
	}, u256.NewUint(9), parentSalt, z.Forward{
		Path:             forwardPath(1, 2),
		TimeoutTimestamp: 999,
		Instruction:      mustCallInstruction(batchCall("sender", "call")),
	})

	uassert.NoError(t, err)
	uassert.True(t, len(hash) == 32)
	uassert.Equal(t, uint32(2), nextSourceChannel)
	packet, err := z.DecodeZkgmPacket(payload.Value)
	uassert.NoError(t, err)
	uassert.True(t, packet.Salt == z.DeriveForwardSalt(parentSalt))
	uassert.True(t, packet.Path.Eq(forwardPath(9, 1, 2)))
	uassert.Equal(t, z.OP_CALL, packet.Instruction.Opcode)
}

func TestBuildForwardNestedRebuildsContinuation(cur realm, t *testing.T) {
	payload, _, nextSourceChannel, err := buildForwardChild(zkgm.RecvRequest{
		DestinationClient: "client-1",
	}, u256.NewUint(5), [32]byte{}, z.Forward{
		Path:             forwardPath(1, 2, 3),
		TimeoutTimestamp: 444,
		Instruction:      mustCallInstruction(batchCall("sender", "call")),
	})

	uassert.NoError(t, err)
	uassert.Equal(t, uint32(2), nextSourceChannel)
	packet, err := z.DecodeZkgmPacket(payload.Value)
	uassert.NoError(t, err)
	uassert.Equal(t, z.OP_FORWARD, packet.Instruction.Opcode)
	nextForward, err := z.DecodeForward(packet.Instruction.Operand)
	uassert.NoError(t, err)
	uassert.True(t, nextForward.Path.Eq(u256.NewUint(3)))
	uassert.Equal(t, uint64(444), nextForward.TimeoutTimestamp)
	uassert.Equal(t, z.OP_CALL, nextForward.Instruction.Opcode)
}

func TestExecuteForwardIntentReturnsOnlyMaker(cur realm, t *testing.T) {
	res, err := (&ZkgmV0{}).executeForward(zkgm.RecvRequest{}, u256.Zero(), [32]byte{}, z.Forward{
		Path:        forwardPath(1, 2),
		Instruction: mustCallInstruction(batchCall("sender", "")),
	}, true)

	uassert.NoError(t, err)
	uassert.True(t, res.Status == types.PacketStatus_Success)
	uassert.True(t, equalBytes(z.ACK_ERR_ONLY_MAKER, res.Acknowledgement))
}

func TestForwardChildAckClearsInFlight(cur realm, t *testing.T) {
	payload, hash := trackedForwardPayload(t)
	parent := types.NewPacket(12, "client-parent-src", "client-parent-dst", 0, mustForwardPayload(z.Forward{Path: forwardPath(1, 2)}))
	zkgm.SetInFlightPacket(cross, zkgm.InFlightKey(hash), parent)

	ack := mustSuccessAck()
	err := (&ZkgmV0{}).Ack(zkgm.AckRequest{
		SourceClient:    "client-2",
		Sequence:        21,
		Acknowledgement: ack,
		Payload:         payload,
	})

	uassert.NoError(t, err)
	_, ok := zkgm.GetInFlightPacket(zkgm.InFlightKey(hash))
	uassert.False(t, ok)
}

func TestForwardChildTimeoutClearsInFlight(cur realm, t *testing.T) {
	payload, hash := trackedForwardPayload(t)
	parent := types.NewPacket(13, "client-parent-src", "client-parent-dst", 0, mustForwardPayload(z.Forward{Path: forwardPath(1, 2)}))
	zkgm.SetInFlightPacket(cross, zkgm.InFlightKey(hash), parent)

	err := (&ZkgmV0{}).Timeout(zkgm.TimeoutRequest{
		SourceClient: "client-2",
		Sequence:     22,
		Payload:      payload,
	})

	uassert.NoError(t, err)
	_, ok := zkgm.GetInFlightPacket(zkgm.InFlightKey(hash))
	uassert.False(t, ok)
}

func TestChannelClientRoundTrip(t *testing.T) {
	uassert.Equal(t, "client-42", channelToClient(42))
	uassert.Equal(t, uint32(42), clientToChannel("client-42"))
	uassert.Equal(t, uint32(0), clientToChannel("07-tendermint-0"))
}

func TestSanityOriginCallerSingleChainNHopStability(cur realm, t *testing.T) {
	mock.Reset(cross)
	mock.SetCaptureOrigin(cross, true)
	const origin = "g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsx"
	testing.SetOriginCaller(origin)

	batch := z.Batch{Instructions: []z.Instruction{
		mustCallInstruction(batchCall("sender", "forward-batch-call")),
	}}
	ack, err := (&ZkgmV0{}).executeBatch(zkgm.RecvRequest{
		SourceClient:      "client-a",
		DestinationClient: "client-b",
		Caller:            origin,
		Relayer:           []byte(origin),
	}, u256.NewUint(1), [32]byte{}, batch, false)

	uassert.NoError(t, err)
	uassert.True(t, len(ack) > 0)
	uassert.Equal(t, origin, mock.LastOriginCaller(cross))
}

func trackedForwardPayload(t *testing.T) (types.Payload, [32]byte) {
	payload, hash, _, err := buildForwardChild(zkgm.RecvRequest{
		DestinationClient: "client-1",
	}, u256.NewUint(8), [32]byte{0xB}, z.Forward{
		Path:        forwardPath(1, 2),
		Instruction: mustCallInstruction(batchCall("sender", "tracked")),
	})
	uassert.NoError(t, err)
	return payload, hash
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

func mustForwardPayload(forward z.Forward) types.Payload {
	forwardBytes, err := z.EncodeForward(forward)
	if err != nil {
		panic(err)
	}
	packetBytes, err := z.EncodeZkgmPacket(z.ZkgmPacket{
		Salt: [32]byte{},
		Path: u256.Zero(),
		Instruction: z.Instruction{
			Version: z.INSTR_VERSION_0,
			Opcode:  z.OP_FORWARD,
			Operand: forwardBytes,
		},
	})
	if err != nil {
		panic(err)
	}
	return types.Payload{
		SourcePort:      PortID,
		DestinationPort: PortID,
		Version:         z.PROTOCOL_VERSION,
		Encoding:        packetEncoding,
		Value:           packetBytes,
	}
}
