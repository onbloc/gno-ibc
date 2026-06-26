package core

import eventattr "gno.land/p/onbloc/event/attr"

const maxPacketDataEventColumns = 50

// MaxPacketDataEventSize returns the packet_data event budget after hexAttr
// encoding.
func MaxPacketDataEventSize() int {
	return maxPacketDataEventColumns * eventattr.MaxValueLen()
}

// PacketDataTooLarge reports whether packet data would exceed the packet_data
// event attribute budget after hexAttr encoding.
func PacketDataTooLarge(data []byte) bool {
	return HexAttrLen(data) > MaxPacketDataEventSize()
}
