package types

// Packet-lifecycle datagrams, mirroring the ibc-union-spec `Datagram` variants
// that carry packets (recv / acknowledgement / timeout / intent / batch).
// Proof heights are plain block numbers (u64), matching the spec.

// MsgPacketRecv delivers one or more packets to their destination, proven
// against the source chain's batch commitment.
type MsgPacketRecv struct {
	Packets     []Packet
	RelayerMsgs [][]byte
	Proof       []byte
	ProofHeight uint64
}

func NewMsgPacketRecv(packets []Packet, relayerMsgs [][]byte, proof []byte, proofHeight uint64) MsgPacketRecv {
	return MsgPacketRecv{
		Packets:     packets,
		RelayerMsgs: relayerMsgs,
		Proof:       proof,
		ProofHeight: proofHeight,
	}
}

// MsgPacketAcknowledgement settles sent packets against the acknowledgements
// committed on the destination chain.
type MsgPacketAcknowledgement struct {
	Packets          []Packet
	Acknowledgements [][]byte
	Proof            []byte
	ProofHeight      uint64
}

func NewMsgPacketAcknowledgement(packets []Packet, acknowledgements [][]byte, proof []byte, proofHeight uint64) MsgPacketAcknowledgement {
	return MsgPacketAcknowledgement{
		Packets:          packets,
		Acknowledgements: acknowledgements,
		Proof:            proof,
		ProofHeight:      proofHeight,
	}
}

// MsgPacketTimeout proves, via non-membership, that a packet was never received
// on the destination chain before its timeout.
type MsgPacketTimeout struct {
	Packet      Packet
	Proof       []byte
	ProofHeight uint64
}

func NewMsgPacketTimeout(packet Packet, proof []byte, proofHeight uint64) MsgPacketTimeout {
	return MsgPacketTimeout{
		Packet:      packet,
		Proof:       proof,
		ProofHeight: proofHeight,
	}
}

// MsgIntentPacketRecv lets a market maker fill packets ahead of proof, carrying
// per-packet market-maker messages instead of a membership proof.
type MsgIntentPacketRecv struct {
	Packets             []Packet
	MarketMakerMessages [][]byte
}

func NewMsgIntentPacketRecv(packets []Packet, marketMakerMessages [][]byte) MsgIntentPacketRecv {
	return MsgIntentPacketRecv{
		Packets:             packets,
		MarketMakerMessages: marketMakerMessages,
	}
}

// MsgBatchSend commits a batch of already-sent packets so they can be proven
// together.
type MsgBatchSend struct {
	Packets []Packet
}

func NewMsgBatchSend(packets []Packet) MsgBatchSend {
	return MsgBatchSend{
		Packets: packets,
	}
}

// MsgBatchAcks commits a batch of acknowledgements for received packets.
type MsgBatchAcks struct {
	Packets []Packet
	Acks    [][]byte
}

func NewMsgBatchAcks(packets []Packet, acks [][]byte) MsgBatchAcks {
	return MsgBatchAcks{
		Packets: packets,
		Acks:    acks,
	}
}

// MsgWriteAcknowledgement writes the acknowledgement for a previously received
// packet (the async-ack settlement path).
type MsgWriteAcknowledgement struct {
	Packet          Packet
	Acknowledgement []byte
}

func NewMsgWriteAcknowledgement(packet Packet, acknowledgement []byte) MsgWriteAcknowledgement {
	return MsgWriteAcknowledgement{
		Packet:          packet,
		Acknowledgement: acknowledgement,
	}
}
