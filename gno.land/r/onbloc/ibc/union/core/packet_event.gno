package core

// MaxPacketDataEventSize returns the packet_data event budget after hexAttr
// encoding. A zero value means event attribute splitting and the packet_data
// budget check are disabled.
func MaxPacketDataEventSize() int {
	config := GetEventConfig()
	if config.MaxEventAttrValueLen <= 0 {
		return 0
	}
	return config.MaxPacketDataEventColumns * config.MaxEventAttrValueLen
}

// PacketDataTooLarge reports whether packet data would exceed the packet_data
// event attribute budget after hexAttr encoding.
func PacketDataTooLarge(data []byte) bool {
	maxSize := MaxPacketDataEventSize()
	if maxSize <= 0 {
		return false
	}
	return HexAttrLen(data) > maxSize
}
