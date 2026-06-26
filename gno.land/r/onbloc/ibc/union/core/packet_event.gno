package core

import "strconv"

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

// eventAttrColumns splits one encoded event attribute value into indexed
// columns. Callers decide whether splitting is enabled before calling this
// helper.
func eventAttrColumns(key string, value string, maxValueLen int) []string {
	if maxValueLen <= 0 {
		panic("max event attr value len must be positive")
	}

	if len(value) == 0 {
		return []string{key + "[0]", ""}
	}

	parts := (len(value) + maxValueLen - 1) / maxValueLen
	attrs := make([]string, 0, parts*2)
	for index := 0; index < parts; index++ {
		start := index * maxValueLen
		end := start + maxValueLen
		if end > len(value) {
			end = len(value)
		}
		attrs = append(attrs, key+"["+strconv.Itoa(index)+"]", value[start:end])
	}

	return attrs
}
