package core

import (
	"chain/params"
	"crypto/keccak256"
	"encoding/hex"
)

var st State

func init() {
	st = newState()
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

// IApp defines the interface for IBC application callbacks. Byte parameters
// use plain []byte (not the typed Bytes wrapper) so foreign-realm apps can
// implement the interface without the cross(cur)-realm typed-slice pitfall.
type IApp interface {
	OnChannelOpenInit(connectionId ConnectionId, channelId ChannelId, version string, relayer address)
	OnChannelOpenTry(connectionId ConnectionId, channelId ChannelId, version string, counterpartyVersion string, relayer address)
	OnChannelOpenAck(channelId ChannelId, counterpartyChannelId ChannelId, counterpartyVersion string, relayer address)
	OnChannelOpenConfirm(channelId ChannelId, relayer address)
	OnChannelCloseInit(channelId ChannelId, relayer address)
	OnChannelCloseConfirm(channelId ChannelId, relayer address)
	OnRecvPacket(packet Packet, relayer address, relayerMsg []byte) RecvPacketResult
	OnIntentRecvPacket(packet Packet, marketMaker address, marketMakerMsg []byte)
	OnAcknowledgementPacket(packet Packet, acknowledgement []byte, relayer address)
	OnTimeoutPacket(packet Packet, relayer address)
}

// RegisterApp registers an IBC application at portId.
//
// Locally-owned ports must use the owning realm's package path bytes.
// Note: portId is []byte to avoid cross(cur)-realm typed slice issues.
func RegisterApp(_ realm, portId []byte, app IApp) {
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
// foreign-realm light clients. Passing a slice backed by readonly or externally
// stored memory can cause ics23 bytes comparisons to panic.
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
