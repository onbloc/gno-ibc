package core

import "testing"

func TestPacketDataTooLarge(cur realm, t *testing.T) {
	resetStore(cur)
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

func TestPacketDataTooLargeUsesEventConfig(cur realm, t *testing.T) {
	resetStore(cur)
	defer resetEventConfigForTest()

	setEventConfig(EventConfig{
		MaxEventAttrValueLen:      4,
		MaxPacketDataEventColumns: 2,
	})

	if got, want := MaxPacketDataEventSize(), 8; got != want {
		t.Fatalf("MaxPacketDataEventSize: got %d want %d", got, want)
	}
	if PacketDataTooLarge(make([]byte, 3)) {
		t.Fatal("3 raw bytes encode to 8 chars and should fit the configured budget")
	}
	if !PacketDataTooLarge(make([]byte, 4)) {
		t.Fatal("4 raw bytes encode to 10 chars and should exceed the configured budget")
	}
}

func TestPacketDataTooLargeDisabledWhenEventAttrSplitDisabled(cur realm, t *testing.T) {
	resetStore(cur)
	defer resetEventConfigForTest()

	setEventConfig(EventConfig{
		MaxEventAttrValueLen:      0,
		MaxPacketDataEventColumns: 2,
	})

	if got := MaxPacketDataEventSize(); got != 0 {
		t.Fatalf("MaxPacketDataEventSize: got %d want 0", got)
	}
	if PacketDataTooLarge(make([]byte, 1024)) {
		t.Fatal("packet data budget check should be disabled when event attr split is disabled")
	}
}
