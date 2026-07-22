package ucs03_zkgm

// send_callback_test.gno tests handleSendCallback's lookup/notify/pop
// behavior in send_callback.gno.

import (
	"testing"

	types "gno.land/p/onbloc/ibc/union/types"

	"gno.land/p/nt/uassert/v0"
	core "gno.land/r/onbloc/ibc/union/core"
)

type recordingSendCallback struct {
	calls   int
	corrID  string
	success bool
	ack     []byte
}

func (r *recordingSendCallback) OnZkgmSendResult(cur realm, corrID string, success bool, ack []byte) error {
	r.calls++
	r.corrID = corrID
	r.success = success
	r.ack = ack
	return nil
}

func TestHandleSendCallback_NoopsWithoutPendingCorr(cur realm, t *testing.T) {
	testStore = newMockStore()
	v := newTestImpl()
	packet := core.NewPacket(types.ChannelId(1), types.ChannelId(2), []byte("data"), 1)

	ok := v.handleSendCallback(0, cur, packet, true, []byte("ack"))

	uassert.False(t, ok)
}

func TestHandleSendCallback_NotifiesRegisteredCallerAndClearsEntry(cur realm, t *testing.T) {
	testStore = newMockStore()
	v := newTestImpl()
	packet := core.NewPacket(types.ChannelId(1), types.ChannelId(2), []byte("data"), 1)
	hash := types.MustCommit(types.CommitPacket(packet)).String()
	callerPkgPath := "gno.land/r/aib/ibc/apps/transfer"

	testStore.SetPendingSendCorr(0, cur, hash, callerPkgPath, "corr-1")
	cb := &recordingSendCallback{}
	testStore.SetSendCallback(0, cur, callerPkgPath, cb)

	ok := v.handleSendCallback(0, cur, packet, true, []byte("ack-bytes"))

	uassert.True(t, ok)
	uassert.Equal(t, 1, cb.calls)
	uassert.Equal(t, "corr-1", cb.corrID)
	uassert.True(t, cb.success)
	uassert.Equal(t, "ack-bytes", string(cb.ack))

	_, _, found := testStore.GetPendingSendCorr(hash)
	uassert.False(t, found)
}

func TestHandleSendCallback_TimeoutReportsFailure(cur realm, t *testing.T) {
	testStore = newMockStore()
	v := newTestImpl()
	packet := core.NewPacket(types.ChannelId(1), types.ChannelId(2), []byte("data"), 1)
	hash := types.MustCommit(types.CommitPacket(packet)).String()
	callerPkgPath := "gno.land/r/aib/ibc/apps/transfer"

	testStore.SetPendingSendCorr(0, cur, hash, callerPkgPath, "corr-2")
	cb := &recordingSendCallback{}
	testStore.SetSendCallback(0, cur, callerPkgPath, cb)

	ok := v.handleSendCallback(0, cur, packet, false, universalErrorAck())

	uassert.True(t, ok)
	uassert.Equal(t, 1, cb.calls)
	uassert.False(t, cb.success)
}

func TestHandleSendCallback_ClearsEntryEvenWithoutRegisteredCallback(cur realm, t *testing.T) {
	testStore = newMockStore()
	v := newTestImpl()
	packet := core.NewPacket(types.ChannelId(1), types.ChannelId(2), []byte("data"), 1)
	hash := types.MustCommit(types.CommitPacket(packet)).String()

	testStore.SetPendingSendCorr(0, cur, hash, "gno.land/r/aib/ibc/apps/transfer", "corr-3")

	ok := v.handleSendCallback(0, cur, packet, true, []byte("ack"))

	uassert.True(t, ok)
	_, _, found := testStore.GetPendingSendCorr(hash)
	uassert.False(t, found)
}
