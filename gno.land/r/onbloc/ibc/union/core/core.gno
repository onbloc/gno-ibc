package core

import (
	"chain/params"
	"chain/runtime"
	"encoding/hex"

	"gno.land/p/onbloc/ibc/union/app"
	"gno.land/p/onbloc/ibc/union/types"
)

var st State

func init() {
	st = newState()
}

// PkgPath returns this core realm's package path.
func PkgPath(cur realm) string {
	return cur.PkgPath()
}

// IBC interface contracts live in pure packages so adapters/apps can implement
// them without importing this realm:
//   - lightclient.ILightClient / lightclient.IForceLightClient
//     in gno.land/p/onbloc/ibc/union/lightclient
//   - app.IApp / app.IIntentApp in gno.land/p/onbloc/ibc/union/app
// core references the pure contracts directly (no re-export aliases).

// RegisterApp registers an IBC application at the caller realm's package path.
func RegisterApp(cur realm, app app.IApp) {
        caller := cur.Previous().PkgPath()
	portId := []byte(caller)
	registerAppAtPort(portId, app)
	emitAppRegisteredEvent(portId, caller, false)
}

// RegisterAppForPort registers an IBC application at an explicit port id. This
// privileged path is for deployment/loaders that install an app on behalf of
// another realm.
func RegisterAppForPort(cur realm, portId []byte, app app.IApp) {
	requireAdmin(cur, "register port")
	runtime.AssertOriginCall()
	registerAppAtPort(portId, app)
	emitAppRegisteredEvent(portId, cur.Previous().PkgPath(), true)
}

func registerAppAtPort(portId []byte, app app.IApp) {
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

func keccak(bz []byte) types.H256 {
	return types.Keccak(bz)
}

// ABI-encoding helpers wrap the pure union/types encoders, which return an
// error (encoding can fail). core treats an encoding failure as a fatal
// invariant violation and panics, matching the Union spec's revert-on-failure
// semantics.

func commitPacketHash(packet types.Packet) types.H256 {
	h, err := types.CommitPacket(packet)
	if err != nil {
		panic(err)
	}
	return h
}

func commitPacketsHash(packets []types.Packet) types.H256 {
	h, err := types.CommitPackets(packets)
	if err != nil {
		panic(err)
	}
	return h
}

func packetCommitmentPath(packet types.Packet) types.H256 {
	h, err := types.PacketCommitmentPath(packet)
	if err != nil {
		panic(err)
	}
	return h
}

func packetAcknowledgementPath(packet types.Packet) types.H256 {
	h, err := types.PacketAcknowledgementPath(packet)
	if err != nil {
		panic(err)
	}
	return h
}

func channelValue(channel types.Channel) types.H256 {
	bz, err := channel.EncodeABI()
	if err != nil {
		panic(err)
	}
	return keccak(bz)
}

func connectionValue(connection types.Connection) types.H256 {
	bz, err := connection.EncodeABI()
	if err != nil {
		panic(err)
	}
	return keccak(bz)
}

// commit writes an IBC commitment to chain params so the counterparty can
// prove it via an ABCI merkle query. This is the public, provable mirror of the
// realm's in-memory state: State.save*/delete* methods keep their own map for
// fast local lookups and call commit so the same value is exposed under the
// canonical commitment key (types.*Path). The two writes are a pair — local map
// for this realm's logic, chain params for the counterparty's membership proof.
//
// Keys follow the ibc-union (EVM storage layout) schema owned by the host
// package (gno.land/p/onbloc/ibc/host), not classic IBC (ICS-024) string keys,
// so commitments stay provable against Union relayers and EVM counterparties.
func commit(key types.H256, value types.H256) {
	params.SetBytes(hex.EncodeToString(key[:]), value[:])
}

// h256Bytes returns a fresh byte slice containing h.
//
// Use it when passing package-level types.H256 values such as types.COMMITMENT_MAGIC to
// foreign-realm light clients. ics23 may copy and append against the input, so
// callers should pass a freshly allocated slice.
func h256Bytes(h types.H256) []byte {
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

func h256String(h types.H256) string {
	return hexString(h[:])
}
