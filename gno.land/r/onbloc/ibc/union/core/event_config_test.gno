package core

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
	"gno.land/r/onbloc/ibc/union/access"
)

func TestGetEventConfigDefaults(cur realm, t *testing.T) {
	resetStore(cur)

	got := GetEventConfig()
	if got.MaxEventAttrValueLen != defaultMaxEventAttrValueLen {
		t.Fatalf("MaxEventAttrValueLen: got %d want %d", got.MaxEventAttrValueLen, defaultMaxEventAttrValueLen)
	}
	if got.MaxPacketDataEventColumns != defaultMaxPacketDataEventColumns {
		t.Fatalf("MaxPacketDataEventColumns: got %d want %d", got.MaxPacketDataEventColumns, defaultMaxPacketDataEventColumns)
	}
	if gotSize, wantSize := MaxPacketDataEventSize(), defaultMaxEventAttrValueLen*defaultMaxPacketDataEventColumns; gotSize != wantSize {
		t.Fatalf("MaxPacketDataEventSize: got %d want %d", gotSize, wantSize)
	}
}

func TestSetEventConfigAccessControlled(cur realm, t *testing.T) {
	resetStore(cur)
	defer resetEventConfigForTest()

	next := EventConfig{
		MaxEventAttrValueLen:      8,
		MaxPacketDataEventColumns: 3,
	}

	requireSelectorProtectedForTest(cur, SelectorSetEventConfig)
	uassert.AbortsContains(t, cur, access.ErrAccessManagerUnauthorizedCall, func(cur realm) {
		SetEventConfig(cross(cur), next)
	})
	assertEventConfigEqual(t, GetEventConfig(), DefaultEventConfig())

	testing.SetRealm(testing.NewUserRealm(access.DefaultAdminAddress))
	SetEventConfig(cross(cur), next)
	assertEventConfigEqual(t, GetEventConfig(), next)
}

func TestSetEventConfigRejectsInvalidValues(cur realm, t *testing.T) {
	resetStore(cur)

	tests := []struct {
		name       string
		config     EventConfig
		wantPanic  string
		wantConfig EventConfig
	}{
		{
			name: "negative max event attr value len",
			config: EventConfig{
				MaxEventAttrValueLen:      -1,
				MaxPacketDataEventColumns: 3,
			},
			wantPanic:  "max event attr value len must be non-negative",
			wantConfig: DefaultEventConfig(),
		},
		{
			name: "zero max packet data event columns",
			config: EventConfig{
				MaxEventAttrValueLen:      8,
				MaxPacketDataEventColumns: 0,
			},
			wantPanic:  "max packet data event columns must be positive",
			wantConfig: DefaultEventConfig(),
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			resetStore(cur)
			uassert.AbortsContains(t, cur, tc.wantPanic, func(cur realm) {
				testing.SetRealm(testing.NewUserRealm(access.DefaultAdminAddress))
				SetEventConfig(cross(cur), tc.config)
			})
			assertEventConfigEqual(t, GetEventConfig(), tc.wantConfig)
		})
	}
}

func TestEventConfigDrivesPacketDataSplit(cur realm, t *testing.T) {
	resetStore(cur)
	defer resetEventConfigForTest()

	setEventConfig(EventConfig{
		MaxEventAttrValueLen:      4,
		MaxPacketDataEventColumns: 3,
	})

	packet := NewPacket(1, 2, []byte{0x00, 0x01}, 10)
	attrs := packetEventBaseAttrs(packet)

	assertStringSliceEqual(t, attrs[4:], []string{
		"packet_data[0]", "0x00",
		"packet_data[1]", "01",
	})
}

func TestEventConfigDisablesPacketDataSplit(cur realm, t *testing.T) {
	resetStore(cur)
	defer resetEventConfigForTest()

	setEventConfig(EventConfig{
		MaxEventAttrValueLen:      0,
		MaxPacketDataEventColumns: 3,
	})

	packet := NewPacket(1, 2, []byte{0x00, 0x01}, 10)
	attrs := packetEventBaseAttrs(packet)

	assertStringSliceEqual(t, attrs[4:], []string{
		"packet_data", "0x0001",
	})
}

func assertEventConfigEqual(t *testing.T, got EventConfig, want EventConfig) {
	t.Helper()

	if got.MaxEventAttrValueLen != want.MaxEventAttrValueLen {
		t.Fatalf("MaxEventAttrValueLen: got %d want %d", got.MaxEventAttrValueLen, want.MaxEventAttrValueLen)
	}
	if got.MaxPacketDataEventColumns != want.MaxPacketDataEventColumns {
		t.Fatalf("MaxPacketDataEventColumns: got %d want %d", got.MaxPacketDataEventColumns, want.MaxPacketDataEventColumns)
	}
}

func resetEventConfigForTest() {
	eventConfig = DefaultEventConfig()
}
