package core

import (
	"gno.land/p/onbloc/ibc/union/types"
)

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

func Render(_ string) string {
	return "next client id: " + types.ClientId(uint32(store.clientSeq)+1).String()
}
