package core

// MaxPacketDataEventSize returns the configured packet_data event budget after
// hexAttr encoding.
//
// The budget is MaxPacketDataEventColumns * MaxEventAttrValueLen and is
// enforced only when SplitEventAttrs is true.
func MaxPacketDataEventSize() int {
	config := GetEventConfig()
	return int(config.MaxPacketDataEventColumns * config.MaxEventAttrValueLen)
}

// PacketDataTooLarge reports whether data exceeds the configured packet_data
// event budget after hexAttr encoding.
//
// It returns false when SplitEventAttrs is false because that mode intentionally
// disables packet_data size checks.
func PacketDataTooLarge(data []byte) bool {
	if !GetEventConfig().SplitEventAttrs {
		return false
	}

	return HexAttrLen(data) > MaxPacketDataEventSize()
}
