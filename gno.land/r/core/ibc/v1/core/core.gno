package core

import (
	"chain/params"
	"chain/runtime"
	"crypto/keccak256"
	"encoding/hex"
)

var st State

func init() {
	st = newState()
}

// PkgPath returns this core realm's package path.
func PkgPath(cur realm) string {
	return cur.PkgPath()
}

// ILightClient defines the interface that light client adapters must implement.
// Methods that modify adapter state must declare _ realm as the first parameter
// (Gno crossing function requirement for cross(cur)-realm state writes).
type ILightClient interface {
	CreateClient(_ realm, clientId ClientId, clientStateBytes, consensusStateBytes []byte) string
	UpdateClient(_ realm, clientId ClientId, clientMessage []byte) ConsensusStateUpdate
	VerifyMembership(clientId ClientId, height Height, proof []byte, key []byte, value []byte)
	VerifyNonMembership(clientId ClientId, height Height, proof []byte, key []byte)
	GetTimestamp(clientId ClientId, height Height) Timestamp
	GetLatestHeight(clientId ClientId) Height
	GetStatus(clientId ClientId) Status
}

// IForceLightClient is an optional interface implemented by light clients that
// support admin-initiated force updates (e.g. to recover an expired client).
// It is separate from ILightClient because force-update is not part of the
// standard light client spec — it is a chain-operator escape hatch.
type IForceLightClient interface {
	ForceUpdateClient(cur realm, clientId ClientId, clientStateBytes, consensusStateBytes []byte) ConsensusStateUpdate
}

// IApp defines the interface for IBC application callbacks. Byte parameters
// use plain []byte (not the typed Bytes wrapper) so foreign-realm apps can
// implement the interface without the cross(cur)-realm typed-slice pitfall.
type IApp interface {
	OnChannelOpenInit(cur realm, connectionId ConnectionId, channelId ChannelId, version string, relayer address)
	OnChannelOpenTry(cur realm, connectionId ConnectionId, channelId ChannelId, version string, counterpartyVersion string, relayer address)
	OnChannelOpenAck(cur realm, channelId ChannelId, counterpartyChannelId ChannelId, counterpartyVersion string, relayer address)
	OnChannelOpenConfirm(cur realm, channelId ChannelId, relayer address)
	OnChannelCloseInit(cur realm, channelId ChannelId, relayer address)
	OnChannelCloseConfirm(cur realm, channelId ChannelId, relayer address)
	OnRecvPacket(cur realm, packet Packet, relayer address, relayerMsg []byte) RecvPacketResult
	OnIntentRecvPacket(cur realm, packet Packet, marketMaker address, marketMakerMsg []byte) RecvPacketResult
	OnAcknowledgementPacket(cur realm, packet Packet, acknowledgement []byte, relayer address)
	OnTimeoutPacket(cur realm, packet Packet, relayer address)
}

// RegisterApp registers an IBC application at the caller realm's package path.
func RegisterApp(cur realm, app IApp) {
	registerAppAtPort([]byte(cur.Previous().PkgPath()), app)
}

// RegisterAppForPort registers an IBC application at an explicit port id. This
// privileged path is for deployment/loaders that install an app on behalf of
// another realm.
func RegisterAppForPort(_ realm, portId []byte, app IApp) {
	assertAdmin("register port")
	runtime.AssertOriginCall()
	registerAppAtPort(portId, app)
}

func registerAppAtPort(portId []byte, app IApp) {
	key := string(portId)
	if _, ok := st.ports[key]; ok {
		panic(ErrPortAlreadyRegistered)
	}
	st.ports[key] = app
}

// HasApp reports whether an app is registered at portId.
func HasApp(portId []byte) bool {
	_, ok := st.ports[string(portId)]
	return ok
}

func Render(_ string) string {
	s := "next client id: " + st.nextClientId.String()
	s += "\nregistered clients: ["
	for key := range st.clientRegistry {
		s += " " + string(key)
	}
	s += " ]"
	return s
}

func keccak(bz []byte) H256 {
	sum := keccak256.Sum256(bz)
	var out H256
	for i := range out {
		out[i] = sum[i]
	}
	return out
}

func commit(key H256, value H256) {
	params.SetBytes(hex.EncodeToString(key[:]), value[:])
}

// h256Bytes returns a fresh byte slice containing h.
//
// Use it when passing package-level H256 values such as COMMITMENT_MAGIC to
// foreign-realm light clients. ics23 may copy and append against the input, so
// callers should pass a freshly allocated slice.
func h256Bytes(h H256) []byte {
	out := make([]byte, len(h))
	copy(out, h[:])
	return out
}

func cloneBytes(b []byte) []byte {
	out := make([]byte, len(b))
	copy(out, b)
	return out
}

func hexString(b []byte) string {
	return "0x" + hex.EncodeToString(b)
}

// hexAttr encodes b as a lowercase 0x-prefixed hexadecimal string for use in
// chain.Emit attributes.
//
// Use hexAttr for binary attribute values. Converting arbitrary []byte values
// directly to string is lossy for non-UTF-8 input.
func hexAttr(b []byte) string {
	return hexString(b)
}

func h256String(h H256) string {
	return hexString(h[:])
}
