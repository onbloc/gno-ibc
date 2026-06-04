package zkgm

import (
	"testing"

	u256 "gno.land/p/gnoswap/uint256"
)

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

func TestMakePathFromChannel(t *testing.T) {
	// channel 0 in any slot is 0
	if !MakePathFromChannel(0, 0).IsZero() {
		t.Fatal("MakePathFromChannel(0, 0) must be zero")
	}
	if !MakePathFromChannel(0, 5).IsZero() {
		t.Fatal("MakePathFromChannel(0, 5) must be zero")
	}

	// slot 0: identity
	mustEq(t, "make(7,0)", MakePathFromChannel(7, 0), u256.NewUint(7))

	// slot 1: 7 << 32 = 0x7_00000000
	mustEq(t, "make(7,1)", MakePathFromChannel(7, 1),
		u256.NewUint(7<<32))

	// slot 2: 11 << 64 — verify via shift
	want := new(u256.Uint).Lsh(u256.NewUint(11), 64)
	mustEq(t, "make(11,2)", MakePathFromChannel(11, 2), want)

	// slot 7 (highest): 0xFFFFFFFF << 224
	maxU32 := u256.NewUint(0xFFFFFFFF)
	want7 := new(u256.Uint).Lsh(maxU32, 224)
	mustEq(t, "make(maxU32,7)", MakePathFromChannel(0xFFFFFFFF, 7), want7)
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
	// empty
	tail, head := DequeueChannelFromPath(u256.Zero())
	if !tail.IsZero() || head != 0 {
		t.Fatalf("dequeue(0): got (%s, %d) want (0, 0)", tail.Dec(), head)
	}

	// single hop in slot 0
	tail, head = DequeueChannelFromPath(u256.NewUint(7))
	if !tail.IsZero() || head != 7 {
		t.Fatalf("dequeue([7]): got (%s, %d) want (0, 7)", tail.Dec(), head)
	}

	// two hops [3, 5] (slot 0 = 3, slot 1 = 5) → after dequeue path = [5]
	path := pathFromHops(t, 3, 5)
	tail, head = DequeueChannelFromPath(path)
	if head != 3 {
		t.Fatalf("dequeue head: got %d want 3", head)
	}
	mustEq(t, "dequeue tail", tail, u256.NewUint(5))
}

func TestPopChannelFromPath(t *testing.T) {
	// empty
	tail, head := PopChannelFromPath(u256.Zero())
	if !tail.IsZero() || head != 0 {
		t.Fatalf("pop(0): got (%s, %d) want (0, 0)", tail.Dec(), head)
	}

	// single hop in slot 0 → pop returns (0, ch)
	tail, head = PopChannelFromPath(u256.NewUint(7))
	if !tail.IsZero() || head != 7 {
		t.Fatalf("pop([7]): got (%s, %d) want (0, 7)", tail.Dec(), head)
	}

	// channel placed directly in slot 5: pop returns (0, ch)
	p5 := MakePathFromChannel(0xDEADBEEF, 5)
	tail, head = PopChannelFromPath(p5)
	if !tail.IsZero() || head != 0xDEADBEEF {
		t.Fatalf("pop(slot5): got (%s, %x) want (0, deadbeef)", tail.Dec(), head)
	}

	// two hops [3, 5]: pop highest = 5, tail = [3]
	path := pathFromHops(t, 3, 5)
	tail, head = PopChannelFromPath(path)
	if head != 5 {
		t.Fatalf("pop head: got %d want 5", head)
	}
	mustEq(t, "pop tail", tail, u256.NewUint(3))
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

func TestReverseChannelPathEmpty(t *testing.T) {
	got, err := ReverseChannelPath(u256.Zero())
	if err != nil {
		t.Fatalf("reverse(0): %v", err)
	}
	if !got.IsZero() {
		t.Fatalf("reverse(0): got %s want 0", got.Dec())
	}
}

func TestReverseChannelPathSingle(t *testing.T) {
	p := pathFromHops(t, 5)
	got, err := ReverseChannelPath(p)
	if err != nil {
		t.Fatalf("reverse([5]): %v", err)
	}
	mustEq(t, "reverse([5])", got, u256.NewUint(5))
}

func TestReverseChannelPathThreeHops(t *testing.T) {
	// [3, 5, 7] reversed → [7, 5, 3]
	src := pathFromHops(t, 3, 5, 7)
	want := pathFromHops(t, 7, 5, 3)
	got, err := ReverseChannelPath(src)
	if err != nil {
		t.Fatalf("reverse: %v", err)
	}
	mustEq(t, "reverse([3,5,7])", got, want)
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
