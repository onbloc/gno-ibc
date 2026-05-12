package core

func CommitPacket(packet Packet) H256 {
	return CommitPackets([]Packet{packet})
}

func CommitPackets(packets []Packet) H256 {
	return keccak(encodeTopLevelDynamic(encodePacketArray(packets)))
}

func CommitAcks(acks []Bytes) H256 {
	return mergeAck(keccak(encodeTopLevelDynamic(encodeBytesArray(acks))))
}

func encodeTopLevelDynamic(encoded []byte) []byte {
	out := make([]byte, 0, 32+len(encoded))
	out = append(out, u64ToH256(32)...)
	return append(out, encoded...)
}

func encodePacketArray(packets []Packet) []byte {
	out := make([]byte, 0)
	out = append(out, u64ToH256(uint64(len(packets)))...)

	headLen := len(packets) * 32
	tail := make([]byte, 0)
	for _, packet := range packets {
		encoded := packet.EthAbiEncode()
		out = append(out, u64ToH256(uint64(headLen+len(tail)))...)
		tail = append(tail, encoded...)
	}
	return append(out, tail...)
}

func encodeBytesArray(items []Bytes) []byte {
	out := make([]byte, 0)
	out = append(out, u64ToH256(uint64(len(items)))...)

	headLen := len(items) * 32
	tail := make([]byte, 0)
	for _, item := range items {
		encoded := encodeABIBytes(item)
		out = append(out, u64ToH256(uint64(headLen+len(tail)))...)
		tail = append(tail, encoded...)
	}
	return append(out, tail...)
}

func encodeABIBytes(bz []byte) []byte {
	pad := (32 - len(bz)%32) % 32
	out := make([]byte, 0, 32+len(bz)+pad)
	out = append(out, u64ToH256(uint64(len(bz)))...)
	out = append(out, bz...)
	if pad > 0 {
		out = append(out, make([]byte, pad)...)
	}
	return out
}
