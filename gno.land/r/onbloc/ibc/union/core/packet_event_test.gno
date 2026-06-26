package core

import "testing"

func TestPacketDataTooLarge(cur realm, t *testing.T) {
	maxPacketDataBytes := (MaxPacketDataEventSize() - 2) / 2
	realZkgmPacket := mustEncodeRealZkgmPacket(t)
	tests := []struct {
		name string
		data []byte
		want bool
	}{
		{"empty", []byte{}, false},
		{"boundary", make([]byte, maxPacketDataBytes), false},
		{"over boundary", make([]byte, maxPacketDataBytes+1), true},
		{"real zkgm packet", realZkgmPacket, HexAttrLen(realZkgmPacket) > MaxPacketDataEventSize()},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			if got := PacketDataTooLarge(tc.data); got != tc.want {
				t.Fatalf("packet data too large: got %t want %t", got, tc.want)
			}
		})
	}
}
