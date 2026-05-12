package zkgm

import (
	"testing"

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

func (d *dummyImpl) PreChannelOpenInit(channelId core.ChannelId) {
	d.openInitCalled = true
	d.lastChannelId = channelId
}

func (d *dummyImpl) PreChannelOpenTry(channelId core.ChannelId, counterpartyVersion string) {
	d.openTryCalled = true
	d.lastChannelId = channelId
	d.lastCounterpartyVer = counterpartyVersion
}

func (d *dummyImpl) PostChannelOpenAck(channelId core.ChannelId, counterpartyChannelId core.ChannelId) {
	d.openAckCalled = true
	d.lastChannelId = channelId
	d.lastCounterpartyId = counterpartyChannelId
}

func (d *dummyImpl) PostChannelOpenConfirm(channelId core.ChannelId) {
	d.openConfirmCalled = true
	d.lastChannelId = channelId
}

func (d *dummyImpl) PreChannelCloseInit(channelId core.ChannelId) {
	d.closeInitCalled = true
	d.lastChannelId = channelId
}

func (d *dummyImpl) PostChannelCloseConfirm(channelId core.ChannelId) {
	d.closeConfirmCalled = true
	d.lastChannelId = channelId
}

func (d *dummyImpl) Recv(packet core.Packet, relayer address, relayerMsg []byte) core.RecvPacketResult {
	d.recvCalled = true
	if d.recvResult.Status != core.PacketStatusUnknown {
		return d.recvResult
	}
	return core.RecvPacketResult{Status: core.PacketStatusSuccess, Ack: []byte{0x01}}
}

func (d *dummyImpl) IntentRecv(packet core.Packet, marketMaker address, marketMakerMsg []byte) {
	d.recvCalled = true
}

func (d *dummyImpl) Ack(packet core.Packet, ack []byte, relayer address) {
	d.ackCalled = true
}

func (d *dummyImpl) Timeout(packet core.Packet, relayer address) {
	d.timeoutCalled = true
}

func (d *dummyImpl) Send(req SendRequest) ([]byte, error) {
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

func TestAppChannelOpenInitVersion(t *testing.T) {
	resetZkgmForTest()
	d := &dummyImpl{}
	impl = d

	(&App{}).OnChannelOpenInit(1, 2, Version, address("g1relayer"))
	if !d.openInitCalled || d.lastChannelId != 2 {
		t.Fatal("OnChannelOpenInit must delegate to impl")
	}

	uassert.PanicsContains(t, "unsupported channel version", func() {
		(&App{}).OnChannelOpenInit(1, 2, "bad-version", address("g1relayer"))
	})
}

func TestAppChannelOpenTryCounterpartyVersion(t *testing.T) {
	resetZkgmForTest()
	d := &dummyImpl{}
	impl = d

	(&App{}).OnChannelOpenTry(1, 2, Version, Version, address("g1relayer"))
	if !d.openTryCalled || d.lastCounterpartyVer != Version {
		t.Fatal("OnChannelOpenTry must delegate with counterparty version")
	}

	uassert.PanicsContains(t, "unsupported channel version", func() {
		(&App{}).OnChannelOpenTry(1, 2, Version, "bad-version", address("g1relayer"))
	})
}

func TestAppNineMethodsDelegate(t *testing.T) {
	resetZkgmForTest()
	d := &dummyImpl{}
	impl = d
	packet := core.Packet{SourceChannelId: 1, DestinationChannelId: 2, Data: []byte("data")}

	(&App{}).OnChannelOpenAck(2, 3, Version, address("g1relayer"))
	(&App{}).OnChannelOpenConfirm(2, address("g1relayer"))
	(&App{}).OnChannelCloseInit(2, address("g1relayer"))
	(&App{}).OnChannelCloseConfirm(2, address("g1relayer"))
	res := (&App{}).OnRecvPacket(packet, address("g1relayer"), nil)
	(&App{}).OnAcknowledgementPacket(packet, []byte{0x01}, address("g1relayer"))
	(&App{}).OnTimeoutPacket(packet, address("g1relayer"))

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

func TestAppPausedOnlyBlocksRecv(t *testing.T) {
	resetZkgmForTest()
	d := &dummyImpl{}
	impl = d
	paused = true
	packet := core.Packet{SourceChannelId: 1, DestinationChannelId: 2, Data: []byte("data")}

	(&App{}).OnChannelOpenInit(1, 2, Version, address("g1relayer"))
	res := (&App{}).OnRecvPacket(packet, address("g1relayer"), nil)
	(&App{}).OnAcknowledgementPacket(packet, []byte{0x01}, address("g1relayer"))
	(&App{}).OnTimeoutPacket(packet, address("g1relayer"))

	if !d.openInitCalled {
		t.Fatal("paused must not block channel handshake")
	}
	if d.recvCalled {
		t.Fatal("paused must block recv delegation")
	}
	if !d.ackCalled || !d.timeoutCalled {
		t.Fatal("paused must not block ack/timeout callbacks")
	}
	if res.Status != core.PacketStatusFailure || len(res.Ack) == 0 {
		t.Fatal("paused recv must return failure acknowledgement")
	}
}

func TestAppNilImplPolicy(t *testing.T) {
	resetZkgmForTest()
	packet := core.Packet{SourceChannelId: 1, DestinationChannelId: 2, Data: []byte("data")}

	uassert.PanicsContains(t, "impl not set", func() {
		(&App{}).OnChannelOpenInit(1, 2, Version, address("g1relayer"))
	})
	res := (&App{}).OnRecvPacket(packet, address("g1relayer"), nil)
	if res.Status != core.PacketStatusFailure || len(res.Ack) == 0 {
		t.Fatal("nil impl recv must return failure acknowledgement")
	}

	(&App{}).OnAcknowledgementPacket(packet, []byte{0x01}, address("g1relayer"))
	(&App{}).OnTimeoutPacket(packet, address("g1relayer"))
}
