package zkgm

import (
	"testing"

	u256 "gno.land/p/gnoswap/uint256"
)

func TestChannelIDMaskU256(t *testing.T) {
	mustEq(t, "channel mask", channelIDMaskU256(), u256.NewUint(0xFFFFFFFF))
}

func TestMakePathFromChannel(t *testing.T) {
	tests := []struct {
		name     string
		channel  uint32
		slot     int
		want     *u256.Uint
		wantZero bool // true if result must be zero
	}{
		{"ch0 slot0", 0, 0, nil, true},
		{"ch0 slot5", 0, 5, nil, true},
		{"ch7 slot0 identity", 7, 0, u256.NewUint(7), false},
		{"ch7 slot1", 7, 1, u256.NewUint(7 << 32), false},
		{"ch11 slot2", 11, 2, new(u256.Uint).Lsh(u256.NewUint(11), 64), false},
		{"maxU32 slot7", 0xFFFFFFFF, 7, new(u256.Uint).Lsh(u256.NewUint(0xFFFFFFFF), 224), false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := MakePathFromChannel(tt.channel, tt.slot)
			if tt.wantZero {
				if !got.IsZero() {
					t.Fatalf("got %s want zero", got.Dec())
				}
			} else {
				mustEq(t, tt.name, got, tt.want)
			}
		})
	}
}

func TestGetChannelFromPath(t *testing.T) {
	path := new(u256.Uint).Or(
		MakePathFromChannel(3, 0),
		MakePathFromChannel(11, 2),
	)

	tests := []struct {
		name  string
		path  *u256.Uint
		index int
		want  uint32
	}{
		{"empty slot 0", u256.Zero(), 0, 0},
		{"empty slot 7", u256.Zero(), 7, 0},
		{"slot 0", path, 0, 3},
		{"empty middle slot", path, 1, 0},
		{"slot 2", path, 2, 11},
		{"out of range", path, 8, 0},
		{"negative index", path, -1, 0},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := GetChannelFromPath(tt.path, tt.index); got != tt.want {
				t.Fatalf("got %d want %d", got, tt.want)
			}
		})
	}
}

func TestHopCount(t *testing.T) {
	tests := []struct {
		name string
		path *u256.Uint
		want int
	}{
		{"nil", nil, 0},
		{"zero", u256.Zero(), 0},
		{"slot 0", MakePathFromChannel(1, 0), 1},
		{"slot 6", MakePathFromChannel(1, 6), 7},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := HopCount(tt.path); got != tt.want {
				t.Fatalf("got %d want %d", got, tt.want)
			}
		})
	}
}

func TestMakeGetRoundTrip(t *testing.T) {
	for slot := 0; slot < 8; slot++ {
		for _, ch := range []uint32{1, 2, 7, 0xDEADBEEF, 0xFFFFFFFF} {
			p := MakePathFromChannel(ch, slot)
			if got := GetChannelFromPath(p, slot); got != ch {
				t.Fatalf("round-trip slot %d ch %x: got %x", slot, ch, got)
			}
		}
	}
}

func TestDequeueChannelFromPath(t *testing.T) {
	tests := []struct {
		name      string
		path      *u256.Uint
		wantHead  uint32
		wantTail  *u256.Uint
		wantInput *u256.Uint
	}{
		{"empty", u256.Zero(), 0, u256.Zero(), nil},
		{"single hop", u256.NewUint(7), 7, u256.Zero(), nil},
		{"two hops", pathFromHops(t, 3, 5), 3, u256.NewUint(5), nil},
		{"does not mutate input", pathFromHops(t, 3, 5, 7), 3, pathFromHops(t, 5, 7), pathFromHops(t, 3, 5, 7)},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tail, head := DequeueChannelFromPath(tt.path)
			if head != tt.wantHead {
				t.Fatalf("head: got %d want %d", head, tt.wantHead)
			}
			mustEq(t, tt.name+" tail", tail, tt.wantTail)
			if tt.wantInput != nil {
				mustEq(t, tt.name+" input", tt.path, tt.wantInput)
			}
		})
	}
}

func TestPopChannelFromPath(t *testing.T) {
	tests := []struct {
		name      string
		path      *u256.Uint
		wantHead  uint32
		wantTail  *u256.Uint
		wantInput *u256.Uint
	}{
		{"empty", u256.Zero(), 0, u256.Zero(), nil},
		{"single hop", u256.NewUint(7), 7, u256.Zero(), nil},
		{"slot5 only", MakePathFromChannel(0xDEADBEEF, 5), 0xDEADBEEF, u256.Zero(), nil},
		{"two hops", pathFromHops(t, 3, 5), 5, u256.NewUint(3), nil},
		{"does not mutate input", pathFromHops(t, 3, 5, 7), 7, pathFromHops(t, 3, 5), pathFromHops(t, 3, 5, 7)},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tail, head := PopChannelFromPath(tt.path)
			if head != tt.wantHead {
				t.Fatalf("head: got %d want %d", head, tt.wantHead)
			}
			mustEq(t, tt.name+" tail", tail, tt.wantTail)
			if tt.wantInput != nil {
				mustEq(t, tt.name+" input", tt.path, tt.wantInput)
			}
		})
	}
}

func TestUpdateChannelPath(t *testing.T) {
	tests := []struct {
		name    string
		path    *u256.Uint
		channel uint32
		want    *u256.Uint
		wantErr error
		assert  func(t *testing.T, got *u256.Uint)
	}{
		{"empty", u256.Zero(), 7, u256.NewUint(7), nil, nil},
		{"appends", u256.NewUint(7), 5, new(u256.Uint).Or(u256.NewUint(7), MakePathFromChannel(5, 1)), nil, nil},
		{"next channel id zero", u256.Zero(), 0, u256.NewUint(0), nil, nil},
		{"append zero to non-empty", u256.NewUint(7), 0, new(u256.Uint).Or(u256.NewUint(7), u256.NewUint(0)), nil, nil},
		{
			"full width channel appends next slot",
			u256.NewUint(0xFFFFFFFF),
			9,
			nil,
			nil,
			func(t *testing.T, got *u256.Uint) {
				if got := GetChannelFromPath(got, 0); got != 0xFFFFFFFF {
					t.Fatalf("slot 0: got %x", got)
				}
				if got := GetChannelFromPath(got, 1); got != 9 {
					t.Fatalf("slot 1: got %d want 9", got)
				}
				if got := GetChannelFromPath(got, 2); got != 0 {
					t.Fatalf("slot 2: got %d want 0", got)
				}
			},
		},
		{"full", pathFromHops(t, 1, 2, 3, 4, 5, 6, 7, 8), 1, nil, ErrChannelPathFull, nil},
		{
			"slot 7 allowed",
			MakePathFromChannel(1, 6),
			2,
			nil,
			nil,
			func(t *testing.T, got *u256.Uint) {
				if v := GetChannelFromPath(got, 7); v != 2 {
					t.Fatalf("slot 7: got %d want 2", v)
				}
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := UpdateChannelPath(tt.path, tt.channel)
			if err != tt.wantErr {
				t.Fatalf("err: got %v want %v", err, tt.wantErr)
			}
			if tt.wantErr != nil {
				return
			}
			if tt.want != nil {
				mustEq(t, tt.name, got, tt.want)
			}
			if tt.assert != nil {
				tt.assert(t, got)
			}
		})
	}

	p := pathFromHops(t,
		0x80000000,
		0x80000001,
		0x80000002,
		0x80000003,
		0x80000004,
		0x80000005,
		0x80000006,
		0x80000007,
	)
	if got := HopCount(p); got != MaxHops {
		t.Fatalf("HopCount: got %d want %d", got, MaxHops)
	}
	for i := 0; i < MaxHops; i++ {
		want := uint32(0x80000000 + i)
		if got := GetChannelFromPath(p, i); got != want {
			t.Fatalf("slot %d: got %x want %x", i, got, want)
		}
	}
}

func TestReverseChannelPath(t *testing.T) {
	tests := []struct {
		name     string
		hops     []uint32
		wantHops []uint32
	}{
		{"empty", []uint32{}, []uint32{}},
		{"single", []uint32{5}, []uint32{5}},
		{"three hops", []uint32{3, 5, 7}, []uint32{7, 5, 3}},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var src, want *u256.Uint
			if len(tt.hops) > 0 {
				src = pathFromHops(t, tt.hops...)
			} else {
				src = u256.Zero()
			}
			if len(tt.wantHops) > 0 {
				want = pathFromHops(t, tt.wantHops...)
			} else {
				want = u256.Zero()
			}
			got, err := ReverseChannelPath(src)
			if err != nil {
				t.Fatalf("reverse: %v", err)
			}
			mustEq(t, tt.name, got, want)
		})
	}

	t.Run("exactly max hops", func(t *testing.T) {
		src := pathFromHops(t,
			0x80000000,
			0x80000001,
			0x80000002,
			0x80000003,
			0x80000004,
			0x80000005,
			0x80000006,
			0x80000007,
		)
		want := pathFromHops(t,
			0x80000007,
			0x80000006,
			0x80000005,
			0x80000004,
			0x80000003,
			0x80000002,
			0x80000001,
			0x80000000,
		)
		got, err := ReverseChannelPath(src)
		if err != nil {
			t.Fatalf("reverse(max hops): %v", err)
		}
		mustEq(t, "reverse(max hops)", got, want)
	})

	for _, hops := range [][]uint32{
		{1},
		{1, 2},
		{1, 2, 3},
		{9, 8, 7, 6},
	} {
		t.Run("involution", func(t *testing.T) {
			src := pathFromHops(t, hops...)
			once, err := ReverseChannelPath(src)
			if err != nil {
				t.Fatalf("reverse(%v): %v", hops, err)
			}
			twice, err := ReverseChannelPath(once)
			if err != nil {
				t.Fatalf("reverse(reverse(%v)): %v", hops, err)
			}
			mustEq(t, "double reverse", twice, src)
		})
	}
}

// pathFromHops builds a path by sequentially appending hops via
// UpdateChannelPath, mirroring the Rust call sequence used in production.
func pathFromHops(t *testing.T, hops ...uint32) *u256.Uint {
	t.Helper()
	p := u256.Zero()
	for i, h := range hops {
		updated, err := UpdateChannelPath(p, h)
		if err != nil {
			t.Fatalf("UpdateChannelPath(hop %d=%d): %v", i, h, err)
		}
		p = updated
	}
	return p
}

func mustEq(t *testing.T, name string, got, want *u256.Uint) {
	t.Helper()
	if !got.Eq(want) {
		t.Fatalf("%s: got %s want %s", name, got.Dec(), want.Dec())
	}
}
