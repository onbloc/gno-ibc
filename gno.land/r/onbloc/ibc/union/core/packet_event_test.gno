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
		{"real zkgm packet", realZkgmPacket, hexAttrLen(realZkgmPacket) > MaxPacketDataEventSize()},
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

	tests := []struct {
		name       string
		config     EventConfig
		data       []byte
		wantBudget int
		wantLarge  bool
	}{
		{
			name: "split enabled within budget",
			config: EventConfig{
				SplitEventAttrs:           true,
				MaxEventAttrValueLen:      4,
				MaxPacketDataEventColumns: 2,
			},
			data:       make([]byte, 3),
			wantBudget: 8,
			wantLarge:  false,
		},
		{
			name: "split enabled over budget",
			config: EventConfig{
				SplitEventAttrs:           true,
				MaxEventAttrValueLen:      4,
				MaxPacketDataEventColumns: 2,
			},
			data:       make([]byte, 4),
			wantBudget: 8,
			wantLarge:  true,
		},
		{
			name: "split disabled skips budget check",
			config: EventConfig{
				SplitEventAttrs:           false,
				MaxEventAttrValueLen:      4,
				MaxPacketDataEventColumns: 2,
			},
			data:       make([]byte, 1024),
			wantBudget: 8,
			wantLarge:  false,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			setEventConfig(tc.config)

			if got := MaxPacketDataEventSize(); got != tc.wantBudget {
				t.Fatalf("MaxPacketDataEventSize: got %d want %d", got, tc.wantBudget)
			}
			if got := PacketDataTooLarge(tc.data); got != tc.wantLarge {
				t.Fatalf("PacketDataTooLarge: got %t want %t", got, tc.wantLarge)
			}
		})
	}
}
