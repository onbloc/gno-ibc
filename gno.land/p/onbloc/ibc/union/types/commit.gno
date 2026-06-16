package types

// COMMITMENT_MAGIC, COMMITMENT_MAGIC_ACK and mergeAck are defined in path.gno.

// CommitPacket returns the Union commitment hash of a single packet.
func CommitPacket(packet Packet) (H256, error) {
	return CommitPackets([]Packet{packet})
}

// CommitPackets returns the Union commitment hash of a packet batch: the
// keccak of the top-level-dynamic-wrapped ABI packet array.
func CommitPackets(packets []Packet) (H256, error) {
	encoded, err := encodeABIPacketArray(packets)
	if err != nil {
		return H256{}, err
	}

	return keccak(wrapABIEncode(encoded)), nil
}

// CommitAck returns the Union commitment hash of a single acknowledgement.
func CommitAck(ack []byte) H256 {
	return CommitAcks([][]byte{ack})
}

// CommitAcks returns the Union commitment hash of an acknowledgement batch,
// with the leading byte replaced by the commitment magic.
func CommitAcks(acks [][]byte) H256 {
	return mergeAck(keccak(wrapABIEncode(encodeABIBytesArray(acks))))
}
