package core

import (
	"chain/params"
	"chain/runtime"
	"encoding/hex"

	"gno.land/p/onbloc/ibc/types"
)

var st State

func init() {
	st = newState()
}

// PkgPath returns this core realm's package path.
func PkgPath(cur realm) string {
	return cur.PkgPath()
}

// IBC interface contracts (ILightClient/IForceLightClient/IApp/IIntentApp)
// live in the pure packages gno.land/p/onbloc/ibc/{host,app}. core re-exports
// them as aliases in aliases.gno so adapters/apps can implement either the
// pure contract or core.* with no change. See ROLES.md V1.

// RegisterApp registers an IBC application at the caller realm's package path.
func RegisterApp(cur realm, app IApp) {
        caller := cur.Previous().PkgPath()
	portId := []byte(caller)
	registerAppAtPort(portId, app)
	emitAppRegisteredEvent(portId, caller, false)
}

// RegisterAppForPort registers an IBC application at an explicit port id. This
// privileged path is for deployment/loaders that install an app on behalf of
// another realm.
func RegisterAppForPort(cur realm, portId []byte, app IApp) {
	requireAdmin(cur, "register port")
	runtime.AssertOriginCall()
	registerAppAtPort(portId, app)
	emitAppRegisteredEvent(portId, cur.Previous().PkgPath(), true)
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
	return types.Keccak(bz)
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
