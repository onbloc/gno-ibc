package core

import "testing"

func TestIsValidPacketDataSize(cur realm, t *testing.T) {
	resetStore(cur)
	maxPacketDataBytes := (MaxPacketDataEventSize() - 2) / 2
	realZkgmPacket := mustEncodeRealZkgmPacket(t)
	tests := []struct {
		name string
		data []byte
		want bool
	}{
		{"empty", []byte{}, true},
		{"boundary", make([]byte, maxPacketDataBytes), true},
		{"over boundary", make([]byte, maxPacketDataBytes+1), false},
		{"real zkgm packet", realZkgmPacket, hexAttrLen(realZkgmPacket) <= MaxPacketDataEventSize()},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			if got := IsValidPacketDataSize(tc.data); got != tc.want {
				t.Fatalf("is valid packet data size: got %t want %t", got, tc.want)
			}
		})
	}
}

func TestIsValidEventSize(cur realm, t *testing.T) {
	resetStore(cur)
	defer resetEventConfigForTest()

	// MaxEventAttrValueLen=4 => eventColumnPairs(data) = 1 + ceil(hexAttrLen(data)/4).
	// hexAttrLen(b) = len(b)*2+2, so: 0 bytes -> 2 pairs, 3 bytes -> 3 pairs,
	// 5 bytes -> 4 pairs. Combined budget (MaxEventAttrPairs) = 5.
	setEventConfig(EventConfig{
		SplitEventAttrs:      true,
		MaxEventAttrValueLen: 4,
		MaxEventAttrPairs:    5,
	})

	tests := []struct {
		name   string
		fields [][]byte
		want   bool
	}{
		{"no fields", nil, true},
		{"single empty field", [][]byte{{}}, true},
		{"two empty fields", [][]byte{{}, {}}, true},
		{"three empty fields exceed shared budget", [][]byte{{}, {}, {}}, false},
		{"fields at combined boundary", [][]byte{make([]byte, 3), {}}, true},
		{"fields just over combined boundary", [][]byte{make([]byte, 5), {}}, false},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			if got := IsValidEventSize(tc.fields...); got != tc.want {
				t.Fatalf("is valid event size: got %t want %t", got, tc.want)
			}
		})
	}
}

func TestIsValidEventSizeSplitDisabled(cur realm, t *testing.T) {
	resetStore(cur)
	defer resetEventConfigForTest()

	setEventConfig(EventConfig{
		SplitEventAttrs:      false,
		MaxEventAttrValueLen: 4,
		MaxEventAttrPairs:    2,
	})

	huge := make([]byte, 1<<20)
	if got := IsValidEventSize(huge, huge); got != true {
		t.Fatalf("is valid event size with split disabled: got %t want true", got)
	}
}

func TestIsValidPacketDataSizeUsesEventConfig(cur realm, t *testing.T) {
	resetStore(cur)
	defer resetEventConfigForTest()

	tests := []struct {
		name       string
		config     EventConfig
		data       []byte
		wantBudget int
		wantValid  bool
	}{
		{
			name: "split enabled within budget",
			config: EventConfig{
				SplitEventAttrs:      true,
				MaxEventAttrValueLen: 4,
				MaxEventAttrPairs:    2,
			},
			data:       make([]byte, 3),
			wantBudget: 8,
			wantValid:  true,
		},
		{
			name: "split enabled over budget",
			config: EventConfig{
				SplitEventAttrs:      true,
				MaxEventAttrValueLen: 4,
				MaxEventAttrPairs:    2,
			},
			data:       make([]byte, 4),
			wantBudget: 8,
			wantValid:  false,
		},
		{
			name: "split disabled skips budget check",
			config: EventConfig{
				SplitEventAttrs:      false,
				MaxEventAttrValueLen: 4,
				MaxEventAttrPairs:    2,
			},
			data:       make([]byte, 1024),
			wantBudget: 8,
			wantValid:  true,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			setEventConfig(tc.config)

			if got := MaxPacketDataEventSize(); got != tc.wantBudget {
				t.Fatalf("MaxPacketDataEventSize: got %d want %d", got, tc.wantBudget)
			}
			if got := IsValidPacketDataSize(tc.data); got != tc.wantValid {
				t.Fatalf("IsValidPacketDataSize: got %t want %t", got, tc.wantValid)
			}
		})
	}
}
