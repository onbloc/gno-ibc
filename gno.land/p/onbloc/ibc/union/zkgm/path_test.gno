package zkgm

import (
	"testing"

	u256 "gno.land/p/gnoswap/uint256"
)

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
	// empty path returns 0 in every slot
	for i := 0; i < 8; i++ {
		if got := GetChannelFromPath(u256.Zero(), i); got != 0 {
			t.Fatalf("GetChannelFromPath(0, %d) = %d, want 0", i, got)
		}
	}

	// build path manually: slot 0 = 3, slot 2 = 11
	path := new(u256.Uint).Or(
		MakePathFromChannel(3, 0),
		MakePathFromChannel(11, 2),
	)
	if got := GetChannelFromPath(path, 0); got != 3 {
		t.Fatalf("slot 0: got %d want 3", got)
	}
	if got := GetChannelFromPath(path, 1); got != 0 {
		t.Fatalf("slot 1 (empty): got %d want 0", got)
	}
	if got := GetChannelFromPath(path, 2); got != 11 {
		t.Fatalf("slot 2: got %d want 11", got)
	}

	// out-of-range slot returns 0 (no panic)
	if got := GetChannelFromPath(path, 8); got != 0 {
		t.Fatalf("slot 8 (oob): got %d want 0", got)
	}
	if got := GetChannelFromPath(path, -1); got != 0 {
		t.Fatalf("slot -1: got %d want 0", got)
	}
}

func TestHopCountNilAndSparsePath(t *testing.T) {
	if got := HopCount(nil); got != 0 {
		t.Fatalf("HopCount(nil): got %d want 0", got)
	}
	if got := HopCount(u256.Zero()); got != 0 {
		t.Fatalf("HopCount(0): got %d want 0", got)
	}

	path := MakePathFromChannel(1, 6)
	if got := HopCount(path); got != 7 {
		t.Fatalf("HopCount(slot 6): got %d want 7", got)
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
	}{
		{"empty", u256.Zero(), 0, u256.Zero()},
		{"single hop", u256.NewUint(7), 7, u256.Zero()},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tail, head := DequeueChannelFromPath(tt.path)
			if head != tt.wantHead {
				t.Fatalf("head: got %d want %d", head, tt.wantHead)
			}
			mustEq(t, tt.name+" tail", tail, tt.wantTail)
		})
	}

	// two hops [3, 5] (slot 0 = 3, slot 1 = 5) → after dequeue path = [5]
	path := pathFromHops(t, 3, 5)
	tail, head := DequeueChannelFromPath(path)
	if head != 3 {
		t.Fatalf("head: got %d want 3", head)
	}
	mustEq(t, "two hops tail", tail, u256.NewUint(5))
}

func TestDequeueChannelFromPathDoesNotMutateInput(t *testing.T) {
	path := pathFromHops(t, 3, 5, 7)
	before := new(u256.Uint).Set(path)

	_, _ = DequeueChannelFromPath(path)
	mustEq(t, "dequeue input", path, before)
}

func TestPopChannelFromPath(t *testing.T) {
	tests := []struct {
		name     string
		path     *u256.Uint
		wantHead uint32
		wantTail *u256.Uint
	}{
		{"empty", u256.Zero(), 0, u256.Zero()},
		{"single hop", u256.NewUint(7), 7, u256.Zero()},
		{"slot5 only", MakePathFromChannel(0xDEADBEEF, 5), 0xDEADBEEF, u256.Zero()},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tail, head := PopChannelFromPath(tt.path)
			if head != tt.wantHead {
				t.Fatalf("head: got %d want %d", head, tt.wantHead)
			}
			mustEq(t, tt.name+" tail", tail, tt.wantTail)
		})
	}

	// two hops [3, 5]: pop highest = 5, tail = [3]
	path := pathFromHops(t, 3, 5)
	tail, head := PopChannelFromPath(path)
	if head != 5 {
		t.Fatalf("two hops head: got %d want 5", head)
	}
	mustEq(t, "two hops tail", tail, u256.NewUint(3))
}

func TestPopChannelFromPathDoesNotMutateInput(t *testing.T) {
	path := pathFromHops(t, 3, 5, 7)
	before := new(u256.Uint).Set(path)

	_, _ = PopChannelFromPath(path)
	mustEq(t, "pop input", path, before)
}

func TestUpdateChannelPathEmpty(t *testing.T) {
	got, err := UpdateChannelPath(u256.Zero(), 7)
	if err != nil {
		t.Fatalf("update(0, 7): %v", err)
	}
	mustEq(t, "update(0,7)", got, u256.NewUint(7))
}

func TestUpdateChannelPathAppends(t *testing.T) {
	// after [7], next slot is 1 → [7, 5] = (5 << 32) | 7
	p := pathFromHops(t, 7, 5)
	want := new(u256.Uint).Or(u256.NewUint(7), MakePathFromChannel(5, 1))
	mustEq(t, "[7, 5]", p, want)
}

func TestUpdateChannelPathFullWidthChannelAppendsNextSlot(t *testing.T) {
	p, err := UpdateChannelPath(u256.NewUint(0xFFFFFFFF), 9)
	if err != nil {
		t.Fatalf("update(maxU32, 9): %v", err)
	}
	if got := GetChannelFromPath(p, 0); got != 0xFFFFFFFF {
		t.Fatalf("slot 0: got %x", got)
	}
	if got := GetChannelFromPath(p, 1); got != 9 {
		t.Fatalf("slot 1: got %d want 9", got)
	}
	if got := GetChannelFromPath(p, 2); got != 0 {
		t.Fatalf("slot 2: got %d want 0", got)
	}
}

func TestUpdateChannelPathFull(t *testing.T) {
	p := pathFromHops(t, 1, 2, 3, 4, 5, 6, 7, 8)
	_, err := UpdateChannelPath(p, 1)
	if err != ErrChannelPathFull {
		t.Fatalf("expected ErrChannelPathFull, got %v", err)
	}
}

func TestUpdateChannelPathExactlyMaxHopsWithFullWidthChannels(t *testing.T) {
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

func TestUpdateChannelPathSlot7Allowed(t *testing.T) {
	// A path with occupied slots through slot 6 still has room for one more hop.
	p := MakePathFromChannel(1, 6)
	got, err := UpdateChannelPath(p, 2)
	if err != nil {
		t.Fatalf("update(slot6=1, 2): %v", err)
	}
	if v := GetChannelFromPath(got, 7); v != 2 {
		t.Fatalf("slot 7: got %d want 2", v)
	}
}

func TestReverseChannelPath(t *testing.T) {
	tests := []struct {
		name    string
		hops    []uint32
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
}

func TestReverseChannelPathExactlyMaxHops(t *testing.T) {
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
}

func TestReverseChannelPathInvolution(t *testing.T) {
	// reverse(reverse(p)) == p for any path produced by sequential hops
	for _, hops := range [][]uint32{
		{1},
		{1, 2},
		{1, 2, 3},
		{9, 8, 7, 6},
	} {
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
