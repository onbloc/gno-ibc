package attacker

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func TestAppRecvRejectsExternalForgedPacket(cur realm, t *testing.T) {
	uassert.AbortsContains(t, cur, "zkgm: ibc host only", func() {
		AppRecvForgedInitialize(cur)
	})
}

func TestAppCallbacksRejectExternalCalls(cur realm, t *testing.T) {
	uassert.AbortsContains(t, cur, "zkgm: ibc host only", func() {
		AppIntentRecvForgedInitialize(cur)
	})
	uassert.AbortsContains(t, cur, "zkgm: ibc host only", func() {
		AppAckForgedInitialize(cur)
	})
	uassert.AbortsContains(t, cur, "zkgm: ibc host only", func() {
		AppTimeoutForgedInitialize(cur)
	})
}

func TestPrivilegedEntrypointsRejectExternalCalls(cur realm, t *testing.T) {
	uassert.AbortsContains(t, cur, "zkgm: admin only", func() {
		SetRateLimitDisabledDirect(cur)
	})
	uassert.AbortsContains(t, cur, "caller not authorized to batch send", func() {
		BatchSendDirect(cur)
	})
	uassert.AbortsContains(t, cur, "core: implementation not installed", func() {
		WriteForwardAckDirect(cur)
	})
}

func TestRegisterClientRejectsForeignNamespace(cur realm, t *testing.T) {
	uassert.AbortsContains(t, cur, "core: implementation not installed", func() {
		RegisterForeignClientDirect(cur)
	})
}
