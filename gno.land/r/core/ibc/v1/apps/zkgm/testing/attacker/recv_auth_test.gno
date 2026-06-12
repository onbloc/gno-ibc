package attacker

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func TestAppRecvRejectsExternalForgedPacket(cur realm, t *testing.T) {
	uassert.AbortsContains(t, cur, "only core can recv", func() {
		AppRecvForgedInitialize(cur)
	})
}

func TestAppCallbacksRejectExternalCalls(cur realm, t *testing.T) {
	uassert.AbortsContains(t, cur, "only core can intent recv", func() {
		AppIntentRecvForgedInitialize(cur)
	})
	uassert.AbortsContains(t, cur, "only core can ack", func() {
		AppAckForgedInitialize(cur)
	})
	uassert.AbortsContains(t, cur, "only core can timeout", func() {
		AppTimeoutForgedInitialize(cur)
	})
}

func TestProxyMutatorsRejectExternalCalls(cur realm, t *testing.T) {
	uassert.AbortsContains(t, cur, "is not an authorized impl for release native", func() {
		ReleaseNativeDirect(cur)
	})
	uassert.AbortsContains(t, cur, "is not an authorized impl for batch send", func() {
		BatchSendDirect(cur)
	})
	uassert.AbortsContains(t, cur, "is not an authorized impl for write forward ack", func() {
		WriteForwardAckDirect(cur)
	})
}

func TestRegisterClientRejectsForeignNamespace(cur realm, t *testing.T) {
	uassert.AbortsContains(t, cur, "caller not authorized to register client: unauthorized", func() {
		RegisterForeignClientDirect(cur)
	})
}
