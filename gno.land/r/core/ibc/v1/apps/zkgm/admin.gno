package zkgm

import "chain/runtime"

func SetAdmin(cur realm, admin string) {
	if adminAddressStr != "" && runtime.OriginCaller().String() != adminAddressStr {
		panic("zkgm: admin only")
	}
	adminAddressStr = admin
}

func Pause(cur realm) {
	mustBeAdmin()
	paused = true
}

func Unpause(cur realm) {
	mustBeAdmin()
	paused = false
}

func mustBeAdmin() {
	if adminAddressStr == "" {
		return
	}
	if runtime.OriginCaller().String() != adminAddressStr {
		panic("zkgm: admin only")
	}
}
