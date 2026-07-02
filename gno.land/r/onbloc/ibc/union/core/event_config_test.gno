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

func TestEventConfigFieldSettersAccessControlled(cur realm, t *testing.T) {
	defer resetEventConfigForTest()

	tests := []struct {
		name       string
		kind       string
		wantPanic  string
		wantConfig EventConfig
	}{
		{
			name:       "split event attrs unauthorized keeps default",
			kind:       "split event attrs unauthorized",
			wantPanic:  access.ErrAccessManagerUnauthorizedCall,
			wantConfig: DefaultEventConfig(),
		},
		{
			name: "split event attrs admin updates field",
			kind: "split event attrs admin",
			wantConfig: EventConfig{
				SplitEventAttrs:           false,
				MaxEventAttrValueLen:      defaultMaxEventAttrValueLen,
				MaxPacketDataEventColumns: defaultMaxPacketDataEventColumns,
			},
		},
		{
			name:       "max event attr value len unauthorized keeps default",
			kind:       "max event attr value len unauthorized",
			wantPanic:  access.ErrAccessManagerUnauthorizedCall,
			wantConfig: DefaultEventConfig(),
		},
		{
			name: "max event attr value len admin updates field",
			kind: "max event attr value len admin",
			wantConfig: EventConfig{
				SplitEventAttrs:           true,
				MaxEventAttrValueLen:      8,
				MaxPacketDataEventColumns: defaultMaxPacketDataEventColumns,
			},
		},
		{
			name:       "max packet data event columns unauthorized keeps default",
			kind:       "max packet data event columns unauthorized",
			wantPanic:  access.ErrAccessManagerUnauthorizedCall,
			wantConfig: DefaultEventConfig(),
		},
		{
			name: "max packet data event columns admin updates field",
			kind: "max packet data event columns admin",
			wantConfig: EventConfig{
				SplitEventAttrs:           true,
				MaxEventAttrValueLen:      defaultMaxEventAttrValueLen,
				MaxPacketDataEventColumns: 3,
			},
		},
	}

	for _, tc := range tests {
		resetStore(cur)
		requireSelectorProtectedForTest(cur, SelectorSetEventConfig)

		if tc.wantPanic != "" {
			uassert.AbortsContains(t, cur, tc.wantPanic, func(cur realm) {
				switch tc.kind {
				case "split event attrs unauthorized":
					SetSplitEventAttrs(cross(cur), false)
				case "max event attr value len unauthorized":
					SetMaxEventAttrValueLen(cross(cur), 8)
				case "max packet data event columns unauthorized":
					SetMaxPacketDataEventColumns(cross(cur), 3)
				}
			})
		} else {
			testing.SetRealm(testing.NewUserRealm(access.DefaultAdminAddress))
			switch tc.kind {
			case "split event attrs admin":
				SetSplitEventAttrs(cross(cur), false)
			case "max event attr value len admin":
				SetMaxEventAttrValueLen(cross(cur), 8)
			case "max packet data event columns admin":
				SetMaxPacketDataEventColumns(cross(cur), 3)
			}
		}
		assertEventConfigEqual(t, GetEventConfig(), tc.wantConfig)
	}
}

func TestSetEventConfigRejectsInvalidValues(cur realm, t *testing.T) {
	resetStore(cur)

	tests := []struct {
		name       string
		kind       string
		config     EventConfig
		wantPanic  string
		wantConfig EventConfig
	}{
		{
			name: "object setter rejects zero max event attr value len",
			kind: "object zero max event attr value len",
			config: EventConfig{
				SplitEventAttrs:           false,
				MaxEventAttrValueLen:      0,
				MaxPacketDataEventColumns: 3,
			},
			wantPanic:  "max event attr value len must be positive",
			wantConfig: DefaultEventConfig(),
		},
		{
			name: "object setter rejects zero max packet data event columns",
			kind: "object zero max packet data event columns",
			config: EventConfig{
				SplitEventAttrs:           true,
				MaxEventAttrValueLen:      8,
				MaxPacketDataEventColumns: 0,
			},
			wantPanic:  "max packet data event columns must be positive",
			wantConfig: DefaultEventConfig(),
		},
		{
			name:       "field setter rejects zero max event attr value len",
			kind:       "field zero max event attr value len",
			wantPanic:  "max event attr value len must be positive",
			wantConfig: DefaultEventConfig(),
		},
		{
			name:       "field setter rejects zero max packet data event columns",
			kind:       "field zero max packet data event columns",
			wantPanic:  "max packet data event columns must be positive",
			wantConfig: DefaultEventConfig(),
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			resetStore(cur)
			uassert.AbortsContains(t, cur, tc.wantPanic, func(cur realm) {
				testing.SetRealm(testing.NewUserRealm(access.DefaultAdminAddress))
				switch tc.kind {
				case "object zero max event attr value len", "object zero max packet data event columns":
					SetEventConfig(cross(cur), tc.config)
				case "field zero max event attr value len":
					SetMaxEventAttrValueLen(cross(cur), 0)
				case "field zero max packet data event columns":
					SetMaxPacketDataEventColumns(cross(cur), 0)
				}
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
				"packet_data_size", "8",
				"packet_data[0]", "AAEC",
				"packet_data[1]", "Aw==",
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
				"packet_data", "AAECAw==",
			},
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			setEventConfig(tc.config)

			packet := NewPacket(1, 2, []byte{0x00, 0x01, 0x02, 0x03}, 10)
			attrs := packetEventBaseAttrs(packet)

			assertStringSliceEqual(t, attrs[2:], tc.want)
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
