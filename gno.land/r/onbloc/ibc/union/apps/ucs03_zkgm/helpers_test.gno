package zkgm

import (
	"testing"

	types "gno.land/p/onbloc/ibc/union/types"

	z "gno.land/p/onbloc/ibc/union/zkgm"
	"gno.land/r/onbloc/ibc/union/access"
	core "gno.land/r/onbloc/ibc/union/core"
)

// helpers_test.gno holds the shared proxy-test fixtures: a recording dummy IApp
// used to assert the App receiver surface delegates correctly, and the reset
// helper that returns the proxy package state to a clean baseline between tests.

var coreRealmPath = access.CoreRealmPath

// dummyImpl is a recording stub implementing the injected IApp contract. It lets
// the App-receiver tests assert delegation/gating without the real v1 logic.
type dummyImpl struct {
	openInitCalled     bool
	openTryCalled      bool
	openAckCalled      bool
	openConfirmCalled  bool
	closeInitCalled    bool
	closeConfirmCalled bool
	recvCalled         bool
	intentRecvCalled   bool
	ackCalled          bool
	timeoutCalled      bool
	sendCalled         bool

	recvResult          types.RecvPacketResult
	lastChannelId       types.ChannelId
	lastCounterpartyId  types.ChannelId
	lastCounterpartyVer string
}

var _ IApp = &dummyImpl{}

func (d *dummyImpl) OnChannelOpenInit(_ int, rlm realm, connectionId types.ConnectionId, channelId types.ChannelId, version string, relayer address) {
	d.openInitCalled = true
	d.lastChannelId = channelId
}

func (d *dummyImpl) OnChannelOpenTry(_ int, rlm realm, connectionId types.ConnectionId, channelId types.ChannelId, version string, counterpartyVersion string, relayer address) {
	d.openTryCalled = true
	d.lastChannelId = channelId
	d.lastCounterpartyVer = counterpartyVersion
}

func (d *dummyImpl) OnChannelOpenAck(_ int, rlm realm, channelId types.ChannelId, counterpartyChannelId types.ChannelId, counterpartyVersion string, relayer address) {
	d.openAckCalled = true
	d.lastChannelId = channelId
	d.lastCounterpartyId = counterpartyChannelId
	d.lastCounterpartyVer = counterpartyVersion
}

func (d *dummyImpl) OnChannelOpenConfirm(_ int, rlm realm, channelId types.ChannelId, relayer address) {
	d.openConfirmCalled = true
	d.lastChannelId = channelId
}

func (d *dummyImpl) OnChannelCloseInit(_ int, rlm realm, channelId types.ChannelId, relayer address) {
	d.closeInitCalled = true
	d.lastChannelId = channelId
}

func (d *dummyImpl) OnChannelCloseConfirm(_ int, rlm realm, channelId types.ChannelId, relayer address) {
	d.closeConfirmCalled = true
	d.lastChannelId = channelId
}

func (d *dummyImpl) OnRecvPacket(_ int, rlm realm, packet types.Packet, relayer address, relayerMsg []byte) types.RecvPacketResult {
	d.recvCalled = true
	if d.recvResult.Status != types.PacketStatusUnknown {
		return d.recvResult
	}
	return core.NewRecvPacketResult(types.PacketStatusSuccess, []byte{0x01})
}

func (d *dummyImpl) OnIntentRecvPacket(_ int, rlm realm, packet types.Packet, marketMaker address, marketMakerMsg []byte) types.RecvPacketResult {
	d.intentRecvCalled = true
	if d.recvResult.Status != types.PacketStatusUnknown {
		return d.recvResult
	}
	return core.NewRecvPacketResult(types.PacketStatusSuccess, []byte{0x02})
}

func (d *dummyImpl) OnAcknowledgementPacket(_ int, rlm realm, packet types.Packet, acknowledgement []byte, relayer address) {
	d.ackCalled = true
}

func (d *dummyImpl) OnTimeoutPacket(_ int, rlm realm, packet types.Packet, relayer address) {
	d.timeoutCalled = true
}

func (d *dummyImpl) Send(_ int, rlm realm, channelId types.ChannelId, timeoutTimestamp types.Timestamp, salt [32]byte, instruction z.Instruction) types.Packet {
	d.sendCalled = true
	return types.Packet{}
}

// resetZkgmForTest returns the proxy package state to a clean baseline. The
// upgrade model holds the registered impl constructors, the active impl pointer,
// and the `paused` gate.
func resetAccess(cur realm, initialAdmin address) {
	testing.SetRealm(testing.NewUserRealm(initialAdmin))
}

func resetZkgmForTest(cur realm) {
	currentImpl = nil
	currentImplPath = ""
	implConstructors = make(map[string]func(store IStore) IApp)
	paused = false
	resetAccess(cur, access.DefaultAdminAddress)
	// Restore the opt-in rate-limit default (disabled) on the shared singleton.
	store.SetRateLimitDisabled(0, cur, true)
}

// installImplForTest registers a constructor under path and activates it, driving
// the same RegisterImpl -> UpdateImpl flow used in production but without the
// prefix gate, so package-internal tests can install a recording dummy impl.
func installImplForTest(path string, target IApp) {
	implConstructors[path] = func(store IStore) IApp { return target }
	currentImplPath = path
	currentImpl = target
}
