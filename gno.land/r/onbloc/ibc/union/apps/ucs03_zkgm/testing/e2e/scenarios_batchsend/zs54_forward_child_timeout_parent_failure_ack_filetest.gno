// PKGPATH: gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/e2e/scenarios_batchsend
package scenarios_batchsend

import (
	types "gno.land/p/onbloc/ibc/union/types"

	u256 "gno.land/p/gnoswap/uint256"
	z "gno.land/p/onbloc/ibc/union/zkgm"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	e2e "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/e2e"
	impl "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	core "gno.land/r/onbloc/ibc/union/core"
)

const forwardChildTimeoutClientType = types.ClientType("gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/e2e/scenarios_batchsend/forward-child-timeout")

type forwardChildTimeoutLightClient struct{}

func (m *forwardChildTimeoutLightClient) CreateClient(_ realm, clientId types.ClientId, clientStateBytes, consensusStateBytes []byte) string {
	return "forward-child-timeout-chain"
}

func (m *forwardChildTimeoutLightClient) UpdateClient(cur realm, clientId types.ClientId, clientMessage []byte) types.ConsensusStateUpdate {
	return core.NewConsensusStateUpdate(cross(cur), types.NewHeight(1), clientMessage, clientMessage)
}

func (m *forwardChildTimeoutLightClient) VerifyMembership(clientId types.ClientId, height types.Height, proof []byte, key []byte, value []byte) {
}

func (m *forwardChildTimeoutLightClient) VerifyNonMembership(clientId types.ClientId, height types.Height, proof []byte, key []byte) {
}

func (m *forwardChildTimeoutLightClient) GetTimestamp(clientId types.ClientId, height types.Height) types.Timestamp {
	return types.Timestamp(2)
}

func (m *forwardChildTimeoutLightClient) GetLatestHeight(clientId types.ClientId) types.Height {
	return types.NewHeight(1)
}

func (m *forwardChildTimeoutLightClient) GetStatus(clientId types.ClientId) types.Status {
	return types.StatusActive
}

func main(cur realm) {
	impl.Register(cross(cur))
	connectionId := openForwardChildTimeoutConnection(cross(cur))
	parentDestination := openForwardChildTimeoutChannel(cross(cur), connectionId, types.ChannelId(101))
	childSource := openForwardChildTimeoutChannel(cross(cur), connectionId, types.ChannelId(102))

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
	parentPacket := core.NewPacket(cross(cur), types.ChannelId(1), parentDestination,
		e2e.MustPacketData(cross(cur), e2e.MustForwardInstruction(cross(cur), forward)), types.Timestamp(0))
	childPacket := e2e.MustForwardChildPacket(cross(cur), parentPacket, u256.Zero(), [32]byte{}, forward)
	childKey := zkgm.NewInFlightKey(cross(cur), types.MustCommit(types.CommitPacket(childPacket)))

	println("[SCENARIO] 1. recv forward defers parent ack and tracks child")
	core.PacketRecv(cross(cur), types.NewMsgPacketRecv([]types.Packet{parentPacket}, [][]byte{nil}, address(""), nil, 1))
	_, inFlight := zkgm.GetInFlightPacket(childKey)
	println("parent_receipt_after_recv", core.HasPacketReceipt(cross(cur), parentPacket))
	println("parent_ack_after_recv", core.HasAcknowledgement(cross(cur), parentPacket))
	println("child_commitment_after_recv", core.HasPacketCommitment(cross(cur), childPacket))
	println("child_inflight_after_recv", inFlight)

	println("")
	println("[SCENARIO] 2. child timeout writes parent failure ack")
	core.PacketTimeout(cross(cur), types.NewMsgPacketTimeout(childPacket, nil, 1, address("")))
	_, inFlight = zkgm.GetInFlightPacket(childKey)
	println("child_commitment_after_timeout", core.HasPacketCommitment(cross(cur), childPacket))
	println("child_inflight_after_timeout", inFlight)
	println("parent_ack_after_timeout", core.HasAcknowledgement(cross(cur), parentPacket))
	println("parent_ack_is_universal_error", core.AcknowledgementHash(cross(cur), parentPacket).String() == expectedUniversalErrorAckHash(cross(cur)))
	ackHashAfterTimeout := core.AcknowledgementHash(cross(cur), parentPacket).String()

	println("")
	println("[SCENARIO] 3. duplicate child timeout is a no-op")
	core.PacketTimeout(cross(cur), types.NewMsgPacketTimeout(childPacket, nil, 1, address("")))
	_, inFlight = zkgm.GetInFlightPacket(childKey)
	println("child_commitment_after_second_timeout", core.HasPacketCommitment(cross(cur), childPacket))
	println("child_inflight_after_second_timeout", inFlight)
	println("parent_ack_after_second_timeout", core.HasAcknowledgement(cross(cur), parentPacket))
	println("parent_ack_hash_unchanged_after_second_timeout", core.AcknowledgementHash(cross(cur), parentPacket).String() == ackHashAfterTimeout)
	println("forward_child_timeout_parent_failure_ack", "ok")
}

func openForwardChildTimeoutConnection(cur realm) types.ConnectionId {
	if !core.HasClient(forwardChildTimeoutClientType) {
		core.RegisterClient(cross(cur), forwardChildTimeoutClientType, &forwardChildTimeoutLightClient{})
	}
	clientId := core.CreateClient(cross(cur), types.NewMsgCreateClient(forwardChildTimeoutClientType, nil, nil))
	connectionId := core.ConnectionOpenInit(cross(cur), types.NewMsgConnectionOpenInit(clientId, types.ClientId(99)))
	core.ConnectionOpenAck(cross(cur), types.NewMsgConnectionOpenAck(connectionId, types.ConnectionId(77), nil, 1))
	return connectionId
}

func openForwardChildTimeoutChannel(cur realm, connectionId types.ConnectionId, counterpartyChannelId types.ChannelId) types.ChannelId {
	portId := []byte(zkgm.ProxyPkgPath())
	channelId := core.ChannelOpenInit(cross(cur), types.NewMsgChannelOpenInit(portId, portId, connectionId, zkgm.Version))
	core.ChannelOpenAck(cross(cur), types.NewMsgChannelOpenAck(channelId, zkgm.Version, counterpartyChannelId, nil, 1))
	return channelId
}

func expectedUniversalErrorAckHash(cur realm) string {
	ack, err := z.EncodeAck(z.Ack{Tag: u256.NewUint(0), InnerAck: []byte("UNIVERSAL_ERROR")})
	if err != nil {
		panic(err)
	}
	return types.CommitAcks([][]byte{ack}).String()
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
