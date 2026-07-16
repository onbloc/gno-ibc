package core

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
	"gno.land/p/onbloc/ibc/union/types"
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
		{"max event attr pairs", int(got.MaxEventAttrPairs), defaultMaxEventAttrPairs},
		{"max packet data event size", MaxPacketDataEventSize(), defaultMaxEventAttrValueLen * defaultMaxEventAttrPairs},
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
		SplitEventAttrs:      false,
		MaxEventAttrValueLen: 8,
		MaxEventAttrPairs:    3,
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
				SplitEventAttrs:      false,
				MaxEventAttrValueLen: defaultMaxEventAttrValueLen,
				MaxEventAttrPairs:    defaultMaxEventAttrPairs,
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
				SplitEventAttrs:      true,
				MaxEventAttrValueLen: 8,
				MaxEventAttrPairs:    defaultMaxEventAttrPairs,
			},
		},
		{
			name:       "max event attr pairs unauthorized keeps default",
			kind:       "max event attr pairs unauthorized",
			wantPanic:  access.ErrAccessManagerUnauthorizedCall,
			wantConfig: DefaultEventConfig(),
		},
		{
			name: "max event attr pairs admin updates field",
			kind: "max event attr pairs admin",
			wantConfig: EventConfig{
				SplitEventAttrs:      true,
				MaxEventAttrValueLen: defaultMaxEventAttrValueLen,
				MaxEventAttrPairs:    3,
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
				case "max event attr pairs unauthorized":
					SetMaxEventAttrPairs(cross(cur), 3)
				}
			})
		} else {
			testing.SetRealm(testing.NewUserRealm(access.DefaultAdminAddress))
			switch tc.kind {
			case "split event attrs admin":
				SetSplitEventAttrs(cross(cur), false)
			case "max event attr value len admin":
				SetMaxEventAttrValueLen(cross(cur), 8)
			case "max event attr pairs admin":
				SetMaxEventAttrPairs(cross(cur), 3)
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
				SplitEventAttrs:      false,
				MaxEventAttrValueLen: 0,
				MaxEventAttrPairs:    3,
			},
			wantPanic:  "max event attr value len must be positive",
			wantConfig: DefaultEventConfig(),
		},
		{
			name: "object setter rejects zero max event attr pairs",
			kind: "object zero max event attr pairs",
			config: EventConfig{
				SplitEventAttrs:      true,
				MaxEventAttrValueLen: 8,
				MaxEventAttrPairs:    0,
			},
			wantPanic:  "max event attr pairs must be positive",
			wantConfig: DefaultEventConfig(),
		},
		{
			name:       "field setter rejects zero max event attr value len",
			kind:       "field zero max event attr value len",
			wantPanic:  "max event attr value len must be positive",
			wantConfig: DefaultEventConfig(),
		},
		{
			name:       "field setter rejects zero max event attr pairs",
			kind:       "field zero max event attr pairs",
			wantPanic:  "max event attr pairs must be positive",
			wantConfig: DefaultEventConfig(),
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			resetStore(cur)
			uassert.AbortsContains(t, cur, tc.wantPanic, func(cur realm) {
				testing.SetRealm(testing.NewUserRealm(access.DefaultAdminAddress))
				switch tc.kind {
				case "object zero max event attr value len", "object zero max event attr pairs":
					SetEventConfig(cross(cur), tc.config)
				case "field zero max event attr value len":
					SetMaxEventAttrValueLen(cross(cur), 0)
				case "field zero max event attr pairs":
					SetMaxEventAttrPairs(cross(cur), 0)
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
				SplitEventAttrs:      true,
				MaxEventAttrValueLen: 4,
				MaxEventAttrPairs:    3,
			},
			want: []string{
				"packet_data_size", "6",
				"packet_data[0]", "0x00",
				"packet_data[1]", "01",
			},
		},
		{
			name: "unsplit packet data",
			config: EventConfig{
				SplitEventAttrs:      false,
				MaxEventAttrValueLen: 4,
				MaxEventAttrPairs:    3,
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
			attrs := packetSendEventAttrs(packet, types.Channel{}, types.Connection{})

			assertStringSliceEqual(t, attrs[len(attrs)-len(tc.want):], tc.want)
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
	if got.MaxEventAttrPairs != want.MaxEventAttrPairs {
		t.Fatalf("MaxEventAttrPairs: got %d want %d", got.MaxEventAttrPairs, want.MaxEventAttrPairs)
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
