package zkgm

import (
	"testing"

	u256 "gno.land/p/gnoswap/uint256"
)

func TestChannelIDMaskU256(t *testing.T) {
	got := channelIDMaskU256()
	if got == nil {
		t.Fatalf("channelIDMaskU256 returned nil")
	}
	want := u256.NewUint(0xFFFFFFFF)
	if !got.Eq(want) {
		t.Fatalf("channelIDMaskU256 = %s want %s", got.Dec(), want.Dec())
	}
	if got.Uint64() != 0xFFFFFFFF {
		t.Fatalf("Uint64() = %d want %d", got.Uint64(), 0xFFFFFFFF)
	}
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
	tests := []struct {
		name     string
		slots    []int
		channels []uint32
	}{
		{"all slots selected channels", []int{0, 1, 2, 3, 4, 5, 6, 7}, []uint32{1, 2, 7, 0xDEADBEEF, 0xFFFFFFFF}},
		{"slot zero edge cases", []int{0}, []uint32{0, 1, 0xFFFFFFFF, 0x80000000, 0x7FFFFFFF}},
		{"slot seven edge cases", []int{7}, []uint32{0, 1, 0xFFFFFFFF, 0x80000000, 0x7FFFFFFF}},
		{"middle slots boundary values", []int{3, 4}, []uint32{0, 1, 0xFFFF, 0xFFFF0000, 0xFFFFFFFF}},
		{"consecutive slots small channels", []int{0, 1, 2}, []uint32{0, 1, 2, 3, 4, 5}},
		{"high bit channels", []int{0, 1, 6, 7}, []uint32{0x80000000, 0x80000001, 0xFFFFFFFF, 0xFFFFFFFE}},
		{"power of two channels", []int{0, 2, 4, 6}, []uint32{1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096, 8192, 16384, 32768, 65536, 131072, 262144, 524288, 1048576, 2097152, 4194304, 8388608, 16777216, 33554432, 67108864, 134217728, 268435456, 536870912, 1073741824}},
		{"all slots minimal channels", []int{0, 1, 2, 3, 4, 5, 6, 7}, []uint32{0, 1}},
		{"all slots maximal channels", []int{0, 1, 2, 3, 4, 5, 6, 7}, []uint32{0xFFFFFFFF, 0xFFFFFFFE, 0x80000000}},
		{"odd slots odd channels", []int{1, 3, 5, 7}, []uint32{1, 3, 5, 7, 9, 11, 13, 15}},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			for _, slot := range tt.slots {
				for _, ch := range tt.channels {
					p := MakePathFromChannel(ch, slot)
					if got := GetChannelFromPath(p, slot); got != ch {
						t.Fatalf("round-trip slot %d ch %x: got %x", slot, ch, got)
					}
				}
			}
		})
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
		{
			"high-bit max hops",
			pathFromHops(t,
				0x80000000,
				0x80000001,
				0x80000002,
				0x80000003,
				0x80000004,
				0x80000005,
				0x80000006,
			),
			0x80000007,
			nil,
			nil,
			func(t *testing.T, got *u256.Uint) {
				if got := HopCount(got); got != MaxHops {
					t.Fatalf("HopCount: got %d want %d", got, MaxHops)
				}
				for i := 0; i < MaxHops; i++ {
					want := uint32(0x80000000 + i)
					if got := GetChannelFromPath(got, i); got != want {
						t.Fatalf("slot %d: got %x want %x", i, got, want)
					}
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
}

func TestReverseChannelPath(t *testing.T) {
	tests := []struct {
		name     string
		hops     []uint32
		wantHops []uint32
		inverse  bool
	}{
		{"empty", []uint32{}, []uint32{}, false},
		{"single", []uint32{5}, []uint32{5}, false},
		{"three hops", []uint32{3, 5, 7}, []uint32{7, 5, 3}, false},
		{
			"exactly max hops",
			[]uint32{
				0x80000000,
				0x80000001,
				0x80000002,
				0x80000003,
				0x80000004,
				0x80000005,
				0x80000006,
				0x80000007,
			},
			[]uint32{
				0x80000007,
				0x80000006,
				0x80000005,
				0x80000004,
				0x80000003,
				0x80000002,
				0x80000001,
				0x80000000,
			},
			false,
		},
		{"involution single", []uint32{1}, nil, true},
		{"involution two", []uint32{1, 2}, nil, true},
		{"involution three", []uint32{1, 2, 3}, nil, true},
		{"involution four", []uint32{9, 8, 7, 6}, nil, true},
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
			if tt.inverse {
				twice, err := ReverseChannelPath(got)
				if err != nil {
					t.Fatalf("reverse(reverse(%v)): %v", tt.hops, err)
				}
				mustEq(t, "double reverse", twice, src)
				return
			}
			mustEq(t, tt.name, got, want)
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
