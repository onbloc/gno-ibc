// PKGPATH: gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/e2e/scenarios_batchsend
package scenarios_batchsend

import (
	u256 "gno.land/p/gnoswap/uint256"
	z "gno.land/p/onbloc/ibc/zkgm"
	core "gno.land/r/onbloc/ibc/union/core"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	e2e "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/e2e"
	_ "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/loader"
)

const forwardChildTimeoutClientType = core.ClientType("gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/e2e/scenarios_batchsend/forward-child-timeout")

type forwardChildTimeoutLightClient struct{}

func (m *forwardChildTimeoutLightClient) CreateClient(_ realm, clientId core.ClientId, clientStateBytes, consensusStateBytes []byte) string {
	return "forward-child-timeout-chain"
}

func (m *forwardChildTimeoutLightClient) UpdateClient(cur realm, clientId core.ClientId, clientMessage []byte) core.ConsensusStateUpdate {
	return core.NewConsensusStateUpdate(cross(cur), core.Height(1), clientMessage, clientMessage)
}

func (m *forwardChildTimeoutLightClient) VerifyMembership(clientId core.ClientId, height core.Height, proof []byte, key []byte, value []byte) {
}

func (m *forwardChildTimeoutLightClient) VerifyNonMembership(clientId core.ClientId, height core.Height, proof []byte, key []byte) {
}

func (m *forwardChildTimeoutLightClient) GetTimestamp(clientId core.ClientId, height core.Height) core.Timestamp {
	return core.Timestamp(2)
}

func (m *forwardChildTimeoutLightClient) GetLatestHeight(clientId core.ClientId) core.Height {
	return core.Height(1)
}

func (m *forwardChildTimeoutLightClient) GetStatus(clientId core.ClientId) core.Status {
	return core.StatusActive
}

func main(cur realm) {
	connectionId := openForwardChildTimeoutConnection(cross(cur))
	parentDestination := openForwardChildTimeoutChannel(cross(cur), connectionId, core.ChannelId(101))
	childSource := openForwardChildTimeoutChannel(cross(cur), connectionId, core.ChannelId(102))

	forward := z.Forward{
		Path:             e2e.ForwardPath(cross(cur), uint32(parentDestination), uint32(childSource)),
		TimeoutTimestamp: 1,
		Instruction: e2e.MustTokenOrderInstruction(cross(cur), z.TokenOrderV2{
			Sender:      []byte("forward-sender"),
			Receiver:    []byte("forward-receiver"),
			BaseToken:   []byte("ibc/forward-base"),
			BaseAmount:  u256.NewUint(20),
			QuoteToken:  []byte("quote"),
			QuoteAmount: u256.NewUint(20),
			Kind:        z.TOKEN_ORDER_KIND_ESCROW,
		}),
	}
	parentPacket := core.NewPacket(cross(cur), core.ChannelId(1), parentDestination,
		e2e.MustPacketData(cross(cur), e2e.MustForwardInstruction(cross(cur), forward)), 0, core.Timestamp(0))
	childPacket := e2e.MustForwardChildPacket(cross(cur), parentPacket, u256.Zero(), [32]byte{}, forward)
	childKey := zkgm.NewInFlightKey(cross(cur), core.CommitPacket(childPacket))

	println("[SCENARIO] 1. recv forward defers parent ack and tracks child")
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv(cross(cur), []core.Packet{parentPacket}, nil, nil, core.Height(1)))
	_, inFlight := zkgm.GetInFlightPacket(childKey)
	println("parent_receipt_after_recv", core.HasPacketReceipt(cross(cur), parentPacket))
	println("parent_ack_after_recv", core.HasAcknowledgement(cross(cur), parentPacket))
	println("child_commitment_after_recv", core.HasPacketCommitment(cross(cur), childPacket))
	println("child_inflight_after_recv", inFlight)

	println("")
	println("[SCENARIO] 2. child timeout writes parent failure ack")
	core.PacketTimeout(cross(cur), core.NewMsgPacketTimeout(cross(cur), childPacket, nil, core.Height(1)))
	_, inFlight = zkgm.GetInFlightPacket(childKey)
	println("child_commitment_after_timeout", core.HasPacketCommitment(cross(cur), childPacket))
	println("child_inflight_after_timeout", inFlight)
	println("parent_ack_after_timeout", core.HasAcknowledgement(cross(cur), parentPacket))
	println("parent_ack_is_universal_error", core.AcknowledgementHash(cross(cur), parentPacket).String() == expectedUniversalErrorAckHash(cross(cur)))
	ackHashAfterTimeout := core.AcknowledgementHash(cross(cur), parentPacket).String()

	println("")
	println("[SCENARIO] 3. duplicate child timeout is a no-op")
	core.PacketTimeout(cross(cur), core.NewMsgPacketTimeout(cross(cur), childPacket, nil, core.Height(1)))
	_, inFlight = zkgm.GetInFlightPacket(childKey)
	println("child_commitment_after_second_timeout", core.HasPacketCommitment(cross(cur), childPacket))
	println("child_inflight_after_second_timeout", inFlight)
	println("parent_ack_after_second_timeout", core.HasAcknowledgement(cross(cur), parentPacket))
	println("parent_ack_hash_unchanged_after_second_timeout", core.AcknowledgementHash(cross(cur), parentPacket).String() == ackHashAfterTimeout)
	println("forward_child_timeout_parent_failure_ack", "ok")
}

func openForwardChildTimeoutConnection(cur realm) core.ConnectionId {
	if !core.HasClient(forwardChildTimeoutClientType) {
		core.RegisterClient(cross(cur), forwardChildTimeoutClientType, &forwardChildTimeoutLightClient{})
	}
	clientId := core.CreateClient(cross(cur), core.NewMsgCreateClient(cross(cur), forwardChildTimeoutClientType, nil, nil))
	connectionId := core.ConnectionOpenInit(cross(cur), core.NewMsgConnectionOpenInit(cross(cur), clientId, core.ClientId(99)))
	core.ConnectionOpenAck(cross(cur), core.NewMsgConnectionOpenAck(cross(cur), connectionId, core.ConnectionId(77), nil, core.Height(1)))
	return connectionId
}

func openForwardChildTimeoutChannel(cur realm, connectionId core.ConnectionId, counterpartyChannelId core.ChannelId) core.ChannelId {
	portId := []byte(zkgm.ProxyPkgPath())
	channelId := core.ChannelOpenInit(cross(cur), core.NewMsgChannelOpenInit(cross(cur), portId, portId, connectionId, zkgm.Version))
	core.ChannelOpenAck(cross(cur), core.NewMsgChannelOpenAck(cross(cur), channelId, zkgm.Version, counterpartyChannelId, nil, core.Height(1)))
	return channelId
}

func expectedUniversalErrorAckHash(cur realm) string {
	ack, err := z.EncodeAck(z.Ack{Tag: u256.NewUint(0), InnerAck: []byte("UNIVERSAL_ERROR")})
	if err != nil {
		panic(err)
	}
	return core.CommitAcks([][]byte{ack}).String()
}

// Output:
// [SCENARIO] 1. recv forward defers parent ack and tracks child
// parent_receipt_after_recv true
// parent_ack_after_recv false
// child_commitment_after_recv true
// child_inflight_after_recv true
//
// [SCENARIO] 2. child timeout writes parent failure ack
// child_commitment_after_timeout false
// child_inflight_after_timeout false
// parent_ack_after_timeout true
// parent_ack_is_universal_error true
//
// [SCENARIO] 3. duplicate child timeout is a no-op
// child_commitment_after_second_timeout false
// child_inflight_after_second_timeout false
// parent_ack_after_second_timeout true
// parent_ack_hash_unchanged_after_second_timeout true
// forward_child_timeout_parent_failure_ack ok
