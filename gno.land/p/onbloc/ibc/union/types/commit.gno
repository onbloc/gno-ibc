package types

var (
	// COMMITMENT_MAGIC is the sentinel value stored for packet/state
	// commitments. It also seeds the leading byte of acknowledgement hashes via
	// mergeAck.
	COMMITMENT_MAGIC H256 = [32]byte{
		0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	}
	// COMMITMENT_MAGIC_ACK is the sentinel stored for a written packet receipt.
	COMMITMENT_MAGIC_ACK H256 = [32]byte{
		0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	}
)

// mergeAck replaces the leading byte of an acknowledgement hash with the
// commitment magic, matching the ibc-union acknowledgement encoding.
func mergeAck(ack H256) H256 {
	ack[0] = COMMITMENT_MAGIC[0]
	return ack
}

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
