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
