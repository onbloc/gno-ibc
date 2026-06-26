package core

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
	"gno.land/r/onbloc/ibc/union/access"
)

func TestGetEventConfigDefaults(cur realm, t *testing.T) {
	resetStore(cur)

	got := GetEventConfig()
	tests := []struct {
		name string
		got  int
		want int
	}{
		{"split event attrs", boolToInt(got.SplitEventAttrs), 1},
		{"max event attr value len", int(got.MaxEventAttrValueLen), defaultMaxEventAttrValueLen},
		{"max packet data event columns", int(got.MaxPacketDataEventColumns), defaultMaxPacketDataEventColumns},
		{"max packet data event size", MaxPacketDataEventSize(), defaultMaxEventAttrValueLen * defaultMaxPacketDataEventColumns},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			if tc.got != tc.want {
				t.Fatalf("got %d want %d", tc.got, tc.want)
			}
		})
	}
}

func TestSetEventConfigAccessControlled(cur realm, t *testing.T) {
	defer resetEventConfigForTest()

	next := EventConfig{
		SplitEventAttrs:           false,
		MaxEventAttrValueLen:      8,
		MaxPacketDataEventColumns: 3,
	}

	tests := []struct {
		name       string
		admin      bool
		wantPanic  string
		wantConfig EventConfig
	}{
		{
			name:       "unauthorized caller keeps default",
			wantPanic:  access.ErrAccessManagerUnauthorizedCall,
			wantConfig: DefaultEventConfig(),
		},
		{
			name:       "admin caller updates config",
			admin:      true,
			wantConfig: next,
		},
	}

	for _, tc := range tests {
		resetStore(cur)
		requireSelectorProtectedForTest(cur, SelectorSetEventConfig)

		if tc.admin {
			testing.SetRealm(testing.NewUserRealm(access.DefaultAdminAddress))
		}

		if tc.wantPanic != "" {
			uassert.AbortsContains(t, cur, tc.wantPanic, func(cur realm) {
				SetEventConfig(cross(cur), next)
			})
		} else {
			SetEventConfig(cross(cur), next)
		}
		assertEventConfigEqual(t, GetEventConfig(), tc.wantConfig)
	}
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
			name: "zero max event attr value len",
			config: EventConfig{
				SplitEventAttrs:           false,
				MaxEventAttrValueLen:      0,
				MaxPacketDataEventColumns: 3,
			},
			wantPanic:  "max event attr value len must be positive",
			wantConfig: DefaultEventConfig(),
		},
		{
			name: "zero max packet data event columns",
			config: EventConfig{
				SplitEventAttrs:           true,
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

func TestEventConfigDrivesPacketDataAttrs(cur realm, t *testing.T) {
	resetStore(cur)
	defer resetEventConfigForTest()

	tests := []struct {
		name   string
		config EventConfig
		want   []string
	}{
		{
			name: "split packet data",
			config: EventConfig{
				SplitEventAttrs:           true,
				MaxEventAttrValueLen:      4,
				MaxPacketDataEventColumns: 3,
			},
			want: []string{
				"packet_data[0]", "0x00",
				"packet_data[1]", "01",
			},
		},
		{
			name: "unsplit packet data",
			config: EventConfig{
				SplitEventAttrs:           false,
				MaxEventAttrValueLen:      4,
				MaxPacketDataEventColumns: 3,
			},
			want: []string{
				"packet_data", "0x0001",
			},
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			setEventConfig(tc.config)

			packet := NewPacket(1, 2, []byte{0x00, 0x01}, 10)
			attrs := packetEventBaseAttrs(packet)

			assertStringSliceEqual(t, attrs[4:], tc.want)
		})
	}
}

func assertEventConfigEqual(t *testing.T, got EventConfig, want EventConfig) {
	t.Helper()

	if got.SplitEventAttrs != want.SplitEventAttrs {
		t.Fatalf("SplitEventAttrs: got %t want %t", got.SplitEventAttrs, want.SplitEventAttrs)
	}
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

func boolToInt(v bool) int {
	if v {
		return 1
	}
	return 0
}
