package impl

// impl_test.gno covers impl.gno's IBC App receiver surface: channel-handshake
// version enforcement and the closed-channel policy. The packet lifecycle
// (OnRecvPacket / OnAcknowledgementPacket / OnTimeoutPacket) is covered by
// dispatch_test and the per-opcode suites; the user-initiated Send drives
// core.PacketSend and is integration-tested in the e2e suite.

import (
	"testing"

	types "gno.land/p/onbloc/ibc/union/types"

	"gno.land/p/nt/uassert/v0"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
)

func TestOnChannelOpenInitRejectsWrongVersion(cur realm, t *testing.T) {
	uassert.AbortsContains(t, cur, "unsupported channel version", func(cur realm) {
		newTestImpl().OnChannelOpenInit(0, cur, types.ConnectionId(1), types.ChannelId(1), "wrong", address("g1relayer"))
	})
}

func TestOnChannelOpenInitAcceptsProtocolVersion(cur realm, t *testing.T) {
	// The protocol version must pass enforcement without aborting.
	newTestImpl().OnChannelOpenInit(0, cur, types.ConnectionId(1), types.ChannelId(1), zkgm.Version, address("g1relayer"))
}

func TestOnChannelOpenTryRejectsWrongCounterpartyVersion(cur realm, t *testing.T) {
	uassert.AbortsContains(t, cur, "unsupported channel version", func(cur realm) {
		newTestImpl().OnChannelOpenTry(0, cur, types.ConnectionId(1), types.ChannelId(1), zkgm.Version, "wrong", address("g1relayer"))
	})
}

func TestOnChannelOpenAckRejectsWrongCounterpartyVersion(cur realm, t *testing.T) {
	uassert.AbortsContains(t, cur, "unsupported channel version", func(cur realm) {
		newTestImpl().OnChannelOpenAck(0, cur, types.ChannelId(1), types.ChannelId(2), "wrong", address("g1relayer"))
	})
}

func TestOnChannelCloseInitIsRejected(cur realm, t *testing.T) {
	uassert.AbortsContains(t, cur, "channel closing is not allowed", func(cur realm) {
		newTestImpl().OnChannelCloseInit(0, cur, types.ChannelId(1), address("g1relayer"))
	})
}

func TestOnChannelCloseConfirmIsRejected(cur realm, t *testing.T) {
	uassert.AbortsContains(t, cur, "channel closing is not allowed", func(cur realm) {
		newTestImpl().OnChannelCloseConfirm(0, cur, types.ChannelId(1), address("g1relayer"))
	})
}
