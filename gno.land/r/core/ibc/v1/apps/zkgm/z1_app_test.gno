package zkgm

import (
	"testing"

	z "gno.land/p/gnoswap/ibc/zkgm"
	"gno.land/p/nt/uassert/v0"
	core "gno.land/r/core/ibc/v1/core"
)

type dummyImpl struct {
	openInitCalled      bool
	openTryCalled       bool
	openAckCalled       bool
	openConfirmCalled   bool
	closeInitCalled     bool
	closeConfirmCalled  bool
	recvCalled          bool
	ackCalled           bool
	timeoutCalled       bool
	recvResult          core.RecvPacketResult
	lastChannelId       core.ChannelId
	lastCounterpartyId  core.ChannelId
	lastCounterpartyVer string
}

func (d *dummyImpl) PreChannelOpenInit(_ realm, channelId core.ChannelId) {
	d.openInitCalled = true
	d.lastChannelId = channelId
}

func (d *dummyImpl) PreChannelOpenTry(_ realm, channelId core.ChannelId, counterpartyVersion string) {
	d.openTryCalled = true
	d.lastChannelId = channelId
	d.lastCounterpartyVer = counterpartyVersion
}

func (d *dummyImpl) PostChannelOpenAck(_ realm, channelId core.ChannelId, counterpartyChannelId core.ChannelId) {
	d.openAckCalled = true
	d.lastChannelId = channelId
	d.lastCounterpartyId = counterpartyChannelId
}

func (d *dummyImpl) PostChannelOpenConfirm(_ realm, channelId core.ChannelId) {
	d.openConfirmCalled = true
	d.lastChannelId = channelId
}

func (d *dummyImpl) PreChannelCloseInit(_ realm, channelId core.ChannelId) {
	d.closeInitCalled = true
	d.lastChannelId = channelId
}

func (d *dummyImpl) PostChannelCloseConfirm(_ realm, channelId core.ChannelId) {
	d.closeConfirmCalled = true
	d.lastChannelId = channelId
}

func (d *dummyImpl) Recv(cur realm, packet core.Packet, relayer address, relayerMsg []byte) core.RecvPacketResult {
	d.recvCalled = true
	if d.recvResult.Status != core.PacketStatusUnknown {
		return d.recvResult
	}
	return core.NewRecvPacketResult(cross(cur), core.PacketStatusSuccess, []byte{0x01})
}

func (d *dummyImpl) IntentRecv(cur realm, packet core.Packet, marketMaker address, marketMakerMsg []byte) core.RecvPacketResult {
	d.recvCalled = true
	if d.recvResult.Status != core.PacketStatusUnknown {
		return d.recvResult
	}
	return core.NewRecvPacketResult(cross(cur), core.PacketStatusSuccess, []byte{0x02})
}

func (d *dummyImpl) Ack(_ realm, packet core.Packet, ack []byte, relayer address) {
	d.ackCalled = true
}

func (d *dummyImpl) Timeout(_ realm, packet core.Packet, relayer address) {
	d.timeoutCalled = true
}

func (d *dummyImpl) Send(_ realm, req SendRequest) ([]byte, error) {
	return []byte("dummy"), nil
}

func (d *dummyImpl) Render(pkgpath string, path string) string {
	return "dummy"
}

func resetZkgmForTest() {
	impl = nil
	implPath = ""
	allowedImpls = nil
	paused = false
	adminAddressStr = ""
}

func TestAppChannelOpenInitVersion(cur realm, t *testing.T) {
	resetZkgmForTest()
	d := &dummyImpl{}
	impl = d

	(&App{}).OnChannelOpenInit(cur, 1, 2, Version, address("g1relayer"))
	if !d.openInitCalled || d.lastChannelId != 2 {
		t.Fatal("OnChannelOpenInit must delegate to impl")
	}

	uassert.AbortsContains(t, cur, "unsupported channel version", func(cur realm) {
		(&App{}).OnChannelOpenInit(cur, 1, 2, "bad-version", address("g1relayer"))
	})
}

func TestAppChannelOpenTryCounterpartyVersion(cur realm, t *testing.T) {
	resetZkgmForTest()
	d := &dummyImpl{}
	impl = d

	(&App{}).OnChannelOpenTry(cur, 1, 2, Version, Version, address("g1relayer"))
	if !d.openTryCalled || d.lastCounterpartyVer != Version {
		t.Fatal("OnChannelOpenTry must delegate with counterparty version")
	}

	uassert.AbortsContains(t, cur, "unsupported channel version", func(cur realm) {
		(&App{}).OnChannelOpenTry(cur, 1, 2, Version, "bad-version", address("g1relayer"))
	})
}

func TestAppNineMethodsDelegate(cur realm, t *testing.T) {
	resetZkgmForTest()
	d := &dummyImpl{}
	impl = d
	packet := core.NewPacket(cross(cur), 1, 2, []byte("data"), 0, 0)

	(&App{}).OnChannelOpenAck(cur, 2, 3, Version, address("g1relayer"))
	(&App{}).OnChannelOpenConfirm(cur, 2, address("g1relayer"))
	(&App{}).OnChannelCloseInit(cur, 2, address("g1relayer"))
	(&App{}).OnChannelCloseConfirm(cur, 2, address("g1relayer"))
	res := (&App{}).OnRecvPacket(cur, packet, address("g1relayer"), nil)
	(&App{}).OnAcknowledgementPacket(cur, packet, []byte{0x01}, address("g1relayer"))
	(&App{}).OnTimeoutPacket(cur, packet, address("g1relayer"))

	if !d.openAckCalled || !d.openConfirmCalled || !d.closeInitCalled || !d.closeConfirmCalled {
		t.Fatal("channel callbacks must delegate")
	}
	if !d.recvCalled || !d.ackCalled || !d.timeoutCalled {
		t.Fatal("packet callbacks must delegate")
	}
	if res.Status != core.PacketStatusSuccess || len(res.Ack) == 0 {
		t.Fatal("recv result must come from impl")
	}
}

func TestAppPausedBlocksPacketCallbacks(cur realm, t *testing.T) {
	resetZkgmForTest()
	d := &dummyImpl{}
	impl = d
	paused = true
	packet := core.NewPacket(cross(cur), 1, 2, []byte("data"), 0, 0)

	(&App{}).OnChannelOpenInit(cur, 1, 2, Version, address("g1relayer"))
	uassert.AbortsContains(t, cur, "zkgm: paused", func(cur realm) {
		(&App{}).OnRecvPacket(cur, packet, address("g1relayer"), nil)
	})
	uassert.AbortsContains(t, cur, "zkgm: paused", func(cur realm) {
		(&App{}).OnIntentRecvPacket(cur, packet, address("g1maker"), nil)
	})
	uassert.AbortsContains(t, cur, "zkgm: paused", func(cur realm) {
		(&App{}).OnAcknowledgementPacket(cur, packet, []byte{0x01}, address("g1relayer"))
	})
	uassert.AbortsContains(t, cur, "zkgm: paused", func(cur realm) {
		(&App{}).OnTimeoutPacket(cur, packet, address("g1relayer"))
	})

	if !d.openInitCalled {
		t.Fatal("paused must not block channel handshake")
	}
	if d.recvCalled || d.ackCalled || d.timeoutCalled {
		t.Fatal("paused must block recv/ack/timeout delegation")
	}
}

func TestSendRawPausedBlocks(cur realm, t *testing.T) {
	resetZkgmForTest()
	impl = &dummyImpl{}
	paused = true

	uassert.AbortsContains(t, cur, "zkgm: paused", func(cur realm) {
		SendRaw(cur, 1, 0, "0000000000000000000000000000000000000000000000000000000000000000", 0, 0, "")
	})
}

func TestAppNilImplPolicy(cur realm, t *testing.T) {
	resetZkgmForTest()
	packet := core.NewPacket(cross(cur), 1, 2, []byte("data"), 0, 0)

	uassert.AbortsContains(t, cur, "impl not set", func(cur realm) {
		(&App{}).OnChannelOpenInit(cur, 1, 2, Version, address("g1relayer"))
	})
	res := (&App{}).OnRecvPacket(cur, packet, address("g1relayer"), nil)
	if res.Status != core.PacketStatusFailure || len(res.Ack) == 0 {
		t.Fatal("nil impl recv must return failure acknowledgement")
	}

	(&App{}).OnAcknowledgementPacket(cur, packet, []byte{0x01}, address("g1relayer"))
	(&App{}).OnTimeoutPacket(cur, packet, address("g1relayer"))
}

func TestAssertNonZeroTimeoutRejectsZero(cur realm, t *testing.T) {
	uassert.AbortsContains(t, cur, "zkgm: timeout timestamp must be non-zero", func(cur realm) {
		assertNonZeroTimeout(0)
	})
}

func TestAssertNonZeroTimeoutAcceptsNonZero(cur realm, t *testing.T) {
	uassert.NotAborts(t, cur, func(cur realm) {
		assertNonZeroTimeout(core.Timestamp(1))
		assertNonZeroTimeout(core.Timestamp(3600))
	})
}

func TestSendPacketRejectsZeroTimeout(cur realm, t *testing.T) {
	resetZkgmForTest()

	uassert.AbortsContains(t, cur, "zkgm: timeout timestamp must be non-zero", func(cur realm) {
		sendPacket(cur, core.ChannelId(1), 0, [32]byte{}, z.Instruction{}, "g1sender", "")
	})
}

func TestDecodeHexArg(cur realm, t *testing.T) {
	uassert.AbortsContains(t, cur, "invalid salt hex", func(cur realm) {
		mustDecodeHexArg("salt", "zz")
	})
	uassert.AbortsContains(t, cur, "invalid operand hex", func(cur realm) {
		mustDecodeHexArg("operand", "zz")
	})

	got := mustDecodeHexArg("operand", "0xCAFE")
	if len(got) != 2 || got[0] != 0xCA || got[1] != 0xFE {
		t.Fatal("mustDecodeHexArg must accept 0x-prefixed hex")
	}
}
