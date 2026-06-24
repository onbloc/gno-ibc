package core

import (
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/onbloc/ibc/union/app"
	"gno.land/p/onbloc/ibc/union/lightclient"
	"gno.land/p/onbloc/ibc/union/types"
	"gno.land/r/onbloc/ibc/union/access"
)

// proxy_delegation_helpers_test.gno holds the shared fixtures for the proxy
// entrypoint tests: a recording ICore that captures the arguments each public
// proxy function forwards to mustGetImpl(), plus helpers to install it and to
// enter the admin realm so access gates pass.
//
// recordingCore embeds ICore so the interface stays satisfied as the surface
// grows; only the methods exercised by the delegation tests are overridden to
// record their inputs. Calling an un-overridden method would nil-panic, which is
// the intended signal that a new entrypoint needs a delegation test.

type recordingCore struct {
	ICore

	// generic call recorder: method name -> times called
	calls map[string]int

	// client
	registerClientType  types.ClientType
	registerClientImpl  lightclient.ClientImpl
	createClientMsg     types.MsgCreateClient
	updateClientMsg     types.MsgUpdateClient
	forceUpdateMsg      types.MsgForceUpdateClient
	misbehaviourMsg     types.MsgMisbehaviour
	verifyClientId      types.ClientId
	verifyProofHeight   types.Height
	verifyProof         []byte
	verifyPath          []byte
	verifyValue         []byte
	hasClientType       types.ClientType
	hasClientResult     bool
	registerApp         app.IApp

	// connection
	connOpenInitMsg     types.MsgConnectionOpenInit
	connOpenTryMsg      types.MsgConnectionOpenTry
	connOpenAckMsg      types.MsgConnectionOpenAck
	connOpenConfirmMsg  types.MsgConnectionOpenConfirm
	forceConnTryMsg     types.MsgConnectionOpenTry
	forceConnAckMsg     types.MsgConnectionOpenAck
	forceConnConfirmMsg types.MsgConnectionOpenConfirm

	// channel
	chanOpenInitMsg     types.MsgChannelOpenInit
	chanOpenTryMsg      types.MsgChannelOpenTry
	chanOpenAckMsg      types.MsgChannelOpenAck
	chanOpenConfirmMsg  types.MsgChannelOpenConfirm
	chanCloseInitMsg    types.MsgChannelCloseInit
	chanCloseConfirmMsg types.MsgChannelCloseConfirm
	forceChanTryMsg     types.MsgChannelOpenTry
	forceChanAckMsg     types.MsgChannelOpenAck
	forceChanConfirmMsg types.MsgChannelOpenConfirm

	// packet lifecycle
	sendChannelId    types.ChannelId
	sendTimeout      types.Timestamp
	sendData         []byte
	sendResult       types.Packet
	packetRecvMsg    types.MsgPacketRecv
	intentRecvMsg    types.MsgIntentPacketRecv
	packetAckMsg     types.MsgPacketAcknowledgement
	packetTimeoutMsg types.MsgPacketTimeout
	commitMemMsg     types.MsgCommitMembershipProof
	commitNonMemMsg  types.MsgCommitNonMembershipProof
	batchSendMsg     types.MsgBatchSend
	batchAcksMsg     types.MsgBatchAcks
	writeAckMsg      types.MsgWriteAcknowledgement
}

func newRecordingCore() *recordingCore {
	return &recordingCore{calls: make(map[string]int)}
}

func (m *recordingCore) record(name string) { m.calls[name]++ }

// --- Client ---

func (m *recordingCore) RegisterClient(_ int, rlm realm, typ types.ClientType, impl lightclient.ClientImpl) {
	m.record("RegisterClient")
	m.registerClientType = typ
	m.registerClientImpl = impl
}

func (m *recordingCore) HasClient(typ types.ClientType) bool {
	m.record("HasClient")
	m.hasClientType = typ
	return m.hasClientResult
}

func (m *recordingCore) CreateClient(_ int, rlm realm, msg types.MsgCreateClient) {
	m.record("CreateClient")
	m.createClientMsg = msg
}

func (m *recordingCore) UpdateClient(_ int, rlm realm, msg types.MsgUpdateClient) {
	m.record("UpdateClient")
	m.updateClientMsg = msg
}

func (m *recordingCore) ForceUpdateClient(_ int, rlm realm, msg types.MsgForceUpdateClient) {
	m.record("ForceUpdateClient")
	m.forceUpdateMsg = msg
}

func (m *recordingCore) Misbehaviour(_ int, rlm realm, msg types.MsgMisbehaviour) {
	m.record("Misbehaviour")
	m.misbehaviourMsg = msg
}

func (m *recordingCore) VerifyClientMembership(_ int, rlm realm, clientId types.ClientId, proofHeight types.Height, proof, path, value []byte) {
	m.record("VerifyClientMembership")
	m.verifyClientId = clientId
	m.verifyProofHeight = proofHeight
	m.verifyProof = proof
	m.verifyPath = path
	m.verifyValue = value
}

func (m *recordingCore) RegisterApp(_ int, rlm realm, a app.IApp) {
	m.record("RegisterApp")
	m.registerApp = a
}

// --- Connection ---

func (m *recordingCore) ConnectionOpenInit(_ int, rlm realm, msg types.MsgConnectionOpenInit) {
	m.record("ConnectionOpenInit")
	m.connOpenInitMsg = msg
}

func (m *recordingCore) ConnectionOpenTry(_ int, rlm realm, msg types.MsgConnectionOpenTry) {
	m.record("ConnectionOpenTry")
	m.connOpenTryMsg = msg
}

func (m *recordingCore) ConnectionOpenAck(_ int, rlm realm, msg types.MsgConnectionOpenAck) {
	m.record("ConnectionOpenAck")
	m.connOpenAckMsg = msg
}

func (m *recordingCore) ConnectionOpenConfirm(_ int, rlm realm, msg types.MsgConnectionOpenConfirm) {
	m.record("ConnectionOpenConfirm")
	m.connOpenConfirmMsg = msg
}

func (m *recordingCore) ForceConnectionOpenTry(_ int, rlm realm, msg types.MsgConnectionOpenTry) {
	m.record("ForceConnectionOpenTry")
	m.forceConnTryMsg = msg
}

func (m *recordingCore) ForceConnectionOpenAck(_ int, rlm realm, msg types.MsgConnectionOpenAck) {
	m.record("ForceConnectionOpenAck")
	m.forceConnAckMsg = msg
}

func (m *recordingCore) ForceConnectionOpenConfirm(_ int, rlm realm, msg types.MsgConnectionOpenConfirm) {
	m.record("ForceConnectionOpenConfirm")
	m.forceConnConfirmMsg = msg
}

// --- Channel ---

func (m *recordingCore) ChannelOpenInit(_ int, rlm realm, msg types.MsgChannelOpenInit) {
	m.record("ChannelOpenInit")
	m.chanOpenInitMsg = msg
}

func (m *recordingCore) ChannelOpenTry(_ int, rlm realm, msg types.MsgChannelOpenTry) {
	m.record("ChannelOpenTry")
	m.chanOpenTryMsg = msg
}

func (m *recordingCore) ChannelOpenAck(_ int, rlm realm, msg types.MsgChannelOpenAck) {
	m.record("ChannelOpenAck")
	m.chanOpenAckMsg = msg
}

func (m *recordingCore) ChannelOpenConfirm(_ int, rlm realm, msg types.MsgChannelOpenConfirm) {
	m.record("ChannelOpenConfirm")
	m.chanOpenConfirmMsg = msg
}

func (m *recordingCore) ChannelCloseInit(_ int, rlm realm, msg types.MsgChannelCloseInit) {
	m.record("ChannelCloseInit")
	m.chanCloseInitMsg = msg
}

func (m *recordingCore) ChannelCloseConfirm(_ int, rlm realm, msg types.MsgChannelCloseConfirm) {
	m.record("ChannelCloseConfirm")
	m.chanCloseConfirmMsg = msg
}

func (m *recordingCore) ForceChannelOpenTry(_ int, rlm realm, msg types.MsgChannelOpenTry) {
	m.record("ForceChannelOpenTry")
	m.forceChanTryMsg = msg
}

func (m *recordingCore) ForceChannelOpenAck(_ int, rlm realm, msg types.MsgChannelOpenAck) {
	m.record("ForceChannelOpenAck")
	m.forceChanAckMsg = msg
}

func (m *recordingCore) ForceChannelOpenConfirm(_ int, rlm realm, msg types.MsgChannelOpenConfirm) {
	m.record("ForceChannelOpenConfirm")
	m.forceChanConfirmMsg = msg
}

// --- Packet lifecycle ---

func (m *recordingCore) SendPacket(_ int, rlm realm, sourceChannelId types.ChannelId, timeoutTimestamp types.Timestamp, data []byte) types.Packet {
	m.record("SendPacket")
	m.sendChannelId = sourceChannelId
	m.sendTimeout = timeoutTimestamp
	m.sendData = data
	return m.sendResult
}

func (m *recordingCore) PacketRecv(_ int, rlm realm, msg types.MsgPacketRecv) {
	m.record("PacketRecv")
	m.packetRecvMsg = msg
}

func (m *recordingCore) IntentPacketRecv(_ int, rlm realm, msg types.MsgIntentPacketRecv) {
	m.record("IntentPacketRecv")
	m.intentRecvMsg = msg
}

func (m *recordingCore) PacketAcknowledgement(_ int, rlm realm, msg types.MsgPacketAcknowledgement) {
	m.record("PacketAcknowledgement")
	m.packetAckMsg = msg
}

func (m *recordingCore) PacketTimeout(_ int, rlm realm, msg types.MsgPacketTimeout) {
	m.record("PacketTimeout")
	m.packetTimeoutMsg = msg
}

func (m *recordingCore) CommitMembershipProof(_ int, rlm realm, msg types.MsgCommitMembershipProof) {
	m.record("CommitMembershipProof")
	m.commitMemMsg = msg
}

func (m *recordingCore) CommitNonMembershipProof(_ int, rlm realm, msg types.MsgCommitNonMembershipProof) {
	m.record("CommitNonMembershipProof")
	m.commitNonMemMsg = msg
}

func (m *recordingCore) BatchSend(_ int, rlm realm, msg types.MsgBatchSend) {
	m.record("BatchSend")
	m.batchSendMsg = msg
}

func (m *recordingCore) BatchAcks(_ int, rlm realm, msg types.MsgBatchAcks) {
	m.record("BatchAcks")
	m.batchAcksMsg = msg
}

func (m *recordingCore) WriteAcknowledgement(_ int, rlm realm, msg types.MsgWriteAcknowledgement) {
	m.record("WriteAcknowledgement")
	m.writeAckMsg = msg
}

// --- Test harness helpers ---

// installRecordingCore swaps in a fresh recording impl and returns it together
// with a restore func that reinstalls the previous impl. The proxy holds a
// package-level currentImpl, so tests restore it to avoid cross-test leakage.
func installRecordingCore() (*recordingCore, func()) {
	old := currentImpl
	rec := newRecordingCore()
	currentImpl = rec
	return rec, func() { currentImpl = old }
}

// IMPORTANT: testing.SetRealm only affects the frame it is called in; it does
// NOT propagate to the caller. So every access-gated entrypoint call must be
// preceded by an inline testing.SetRealm in the SAME test-body frame. These
// helpers therefore only provide the shared addresses; they never call
// testing.SetRealm on the test's behalf.

// adminRealm is the user realm whose calls satisfy admin-gated selectors
// (Force*, Commit*, RegisterAppForPort). Inline before a gated call:
//
//	testing.SetRealm(adminRealm)
//	ForceUpdateClient(cross(cur), msg)
var adminRealm = testing.NewUserRealm(access.DefaultAdminAddress)

// testRelayer is the address the relayer-gated delegation tests authorize and
// call from; relayerRealm is its user realm.
var (
	testRelayer  = testutils.TestAddress("core-proxy-relayer")
	relayerRealm = testing.NewUserRealm(testRelayer)
)

// NOTE: granting/revoking the relayer role cannot be wrapped in a helper for the
// same reason as testing.SetRealm: access.GrantRole(cross(cur), ...) derives its
// caller from the calling frame, so a helper would present the helper's frame
// (the test realm) and fail the admin check. Tests therefore inline the grant:
//
//	testing.SetRealm(adminRealm)
//	access.GrantRole(cross(cur), RelayerRole, testRelayer)
//	testing.SetRealm(relayerRealm)
//	<relayer-gated entrypoint>
//	testing.SetRealm(adminRealm)
//	access.RevokeRole(cross(cur), RelayerRole, testRelayer)
