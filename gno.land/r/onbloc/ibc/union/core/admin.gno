package core

import (
	"chain/runtime"
)

const defaultAdminAddress = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")

var (
	admin          address
	packageAddress address
	packagePath    string
)

func init(cur realm) {
	// SAFE: admin bootstrap needs the tx signer, not a loader realm that may
	// appear as cur.Previous().
	admin = defaultAdminAddress
	packageAddress = cur.Address()
	packagePath = cur.PkgPath()
}

func PackagePath() string {
	return packagePath
}

// GetAdmin returns the current admin address.
func GetAdmin() address {
	return admin
}

// SetAdmin transfers admin rights to a new address. Only callable by the current admin.
func SetAdmin(cur realm, newAdmin address) {
	runtime.AssertOriginCall()
	requireAdmin(cur, "set admin")

	oldAdmin := admin
	admin = newAdmin
	emitAdminChangedEvent(oldAdmin, newAdmin)
}

func requireAdmin(cur realm, action string) {
	if cur.Previous().Address() != admin {
		panic("caller not authorized to " + action + ": unauthorized")
	}
}
