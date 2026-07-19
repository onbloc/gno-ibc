package ucs03_zkgm

import (
	"testing"

	"gno.land/p/demo/tokens/grc20"
	u256 "gno.land/p/gnoswap/uint256"
	types "gno.land/p/onbloc/ibc/union/types"

	z "gno.land/p/onbloc/ibc/union/zkgm"
	tb "gno.land/p/onbloc/ibc/union/zkgm/tokenbucket"
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
	lastTimeout         types.Timestamp
	lastSalt            [32]byte
	lastInstruction     z.Instruction

	tokenBucket          *tb.TokenBucket
	tokenBucketErr       error
	channelBalance       *u256.Uint
	channelBalanceErr    error
	lastBalanceChannelId types.ChannelId
	lastBalancePath      *u256.Uint
	lastBalanceBaseToken string
	lastBalanceQuote     []byte

	voucherApproveCalled  bool
	voucherTransferCalled bool
	voucherErr            error
	lastVoucherDenom      string
	lastVoucherSpender    address
	lastVoucherTo         address
	lastVoucherAmount     int64
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
	d.lastChannelId = channelId
	d.lastTimeout = timeoutTimestamp
	d.lastSalt = salt
	d.lastInstruction = instruction
	return core.NewPacket(channelId, 0, instruction.Operand, timeoutTimestamp)
}

func (d *dummyImpl) VoucherApprove(_ int, rlm realm, ibcDenom string, spender address, amount int64) error {
	d.voucherApproveCalled = true
	d.lastVoucherDenom = ibcDenom
	d.lastVoucherSpender = spender
	d.lastVoucherAmount = amount
	return d.voucherErr
}

func (d *dummyImpl) VoucherTransfer(_ int, rlm realm, ibcDenom string, to address, amount int64) error {
	d.voucherTransferCalled = true
	d.lastVoucherDenom = ibcDenom
	d.lastVoucherTo = to
	d.lastVoucherAmount = amount
	return d.voucherErr
}

type dummyReceiver struct{}

func (d *dummyReceiver) OnZkgm(cur realm, env z.CallEnv) error {
	return nil
}

func (d *dummyReceiver) OnIntentZkgm(cur realm, env z.IntentCallEnv) error {
	return nil
}

func (d *dummyImpl) GetTokenBucket(denom string) (*tb.TokenBucket, error) {
	return d.tokenBucket, d.tokenBucketErr
}

func (d *dummyImpl) GetChannelBalanceV2(channelId types.ChannelId, path *u256.Uint, baseToken string, quoteToken []byte) (*u256.Uint, error) {
	d.lastBalanceChannelId = channelId
	d.lastBalancePath = path
	d.lastBalanceBaseToken = baseToken
	d.lastBalanceQuote = quoteToken

	return d.channelBalance, d.channelBalanceErr
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

func newVoucherTokenForTest(cur realm, name string, symbol string) (*grc20.Token, *grc20.PrivateLedger) {
	return grc20.NewToken(0, cur, name, symbol, 6)
}
