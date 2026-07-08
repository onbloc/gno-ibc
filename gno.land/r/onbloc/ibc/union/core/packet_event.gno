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

	return hexAttrLen(data) > MaxPacketDataEventSize()
}

// eventColumnPairs returns the number of attr pairs encodedEventAttrs would
// emit for data: one "<key>_size" pair plus one pair per split column.
func eventColumnPairs(data []byte) int {
	maxValueLen := int(GetEventConfig().MaxEventAttrValueLen)
	columns := (hexAttrLen(data) + maxValueLen - 1) / maxValueLen
	if columns < 1 {
		columns = 1
	}

	return 1 + columns
}

// CombinedEventDataTooLarge reports whether fields, split together into one
// host event, would exceed chain.Emit's 64-attr-pair ceiling. Fields within
// PacketDataTooLarge's solo budget individually can still exceed it combined,
// so MaxPacketDataEventColumns is reused as a shared pair budget here.
func CombinedEventDataTooLarge(fields ...[]byte) bool {
	if !GetEventConfig().SplitEventAttrs {
		return false
	}

	total := 0
	for _, data := range fields {
		total += eventColumnPairs(data)
	}

	return total > int(GetEventConfig().MaxPacketDataEventColumns)
}
