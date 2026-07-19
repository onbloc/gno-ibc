package ucs03_zkgm

import (
	"testing"

	types "gno.land/p/onbloc/ibc/union/types"

	"gno.land/p/nt/uassert/v0"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	core "gno.land/r/onbloc/ibc/union/core"
)

const testTrackerPkgPath = "gno.land/r/onbloc/ibc/union/apps/ics20zkgm_adapter"

func TestSendResultKeyDeterministic(t *testing.T) {
	p1 := core.NewPacket(types.ChannelId(1), types.ChannelId(2), []byte("data"), 99)
	p2 := core.NewPacket(types.ChannelId(1), types.ChannelId(2), []byte("data"), 99)
	p3 := core.NewPacket(types.ChannelId(1), types.ChannelId(2), []byte("other"), 99)

	uassert.Equal(t, sendResultKey(p1), sendResultKey(p2))
	uassert.NotEqual(t, sendResultKey(p1), sendResultKey(p3))
}

func TestGetSendResultNotFoundWhenUntracked(cur realm, t *testing.T) {
	testStore = newMockStore()
	v := newTestImpl()

	pkt := core.NewPacket(types.ChannelId(1), types.ChannelId(2), []byte("untracked"), 0)
	_, _, _, found := v.GetSendResult(sendResultKey(pkt))
	uassert.False(t, found)
}

func TestSendTracksThenAckResolvesResult(cur realm, t *testing.T) {
	testStore = newMockStore()
	v := newTestImpl()

	pkt := core.NewPacket(types.ChannelId(1), types.ChannelId(2), []byte("tracked"), 0)
	key := sendResultKey(pkt)

	testStore.SetSendResultTracked(0, cur, key, testTrackerPkgPath)

	// Not yet resolved: found but not resolved.
	_, _, resolved, found := v.GetSendResult(key)
	uassert.True(t, found)
	uassert.False(t, resolved)

	v.emitSendResultResolved(0, cur, pkt, true, []byte("success-ack"))

	successful, ack, resolved, found := v.GetSendResult(key)
	uassert.True(t, found)
	uassert.True(t, resolved)
	uassert.True(t, successful)
	uassert.Equal(t, "success-ack", string(ack))
}

func TestEmitSendResultResolvedNoopsWhenUntracked(cur realm, t *testing.T) {
	testStore = newMockStore()
	v := newTestImpl()

	pkt := core.NewPacket(types.ChannelId(1), types.ChannelId(2), []byte("untracked"), 0)
	// Forward children resolve via handleForwardChild, never reaching this
	// path, so an untracked packet here should simply have nothing recorded.
	v.emitSendResultResolved(0, cur, pkt, true, []byte("ack"))

	_, _, _, found := v.GetSendResult(sendResultKey(pkt))
	uassert.False(t, found)
}

func TestClearSendResultRequiresOriginalTracker(cur realm, t *testing.T) {
	testStore = newMockStore()
	v := newTestImpl()

	pkt := core.NewPacket(types.ChannelId(1), types.ChannelId(2), []byte("tracked"), 0)
	key := sendResultKey(pkt)
	testStore.SetSendResultTracked(0, cur, key, testTrackerPkgPath)

	uassert.AbortsContains(t, cur, zkgm.ErrNotSendResultTracker, func(cur realm) {
		testStore.RemoveSendResult(0, cur, key, "gno.land/r/some/other/realm")
	})

	// Still there after the rejected attempt.
	_, _, _, found := v.GetSendResult(key)
	uassert.True(t, found)

	testStore.RemoveSendResult(0, cur, key, testTrackerPkgPath)
	_, _, _, found = v.GetSendResult(key)
	uassert.False(t, found)
}
