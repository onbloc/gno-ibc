package ics20zkgm_adapter

import (
	"chain"
	"strconv"
)

const (
	AdapterImplUpdatedEvent       = "AdapterImplUpdated"
	AdapterDenomRegisteredEvent   = "AdapterDenomRegistered"
	AdapterDenomUnregisteredEvent = "AdapterDenomUnregistered"
)

func emitAdapterImplUpdatedEvent(callerPkgPath, oldImplPath, newImplPath string) {
	chain.Emit(
		AdapterImplUpdatedEvent,
		"caller_pkg_path", callerPkgPath,
		"old_impl_path", oldImplPath,
		"new_impl_path", newImplPath,
	)
}

func emitAdapterDenomRegisteredEvent(admin address, baseDenom string, zkgmChannelId uint32) {
	chain.Emit(
		AdapterDenomRegisteredEvent,
		"admin", admin.String(),
		"base_denom", baseDenom,
		"zkgm_channel_id", strconv.Itoa(int(zkgmChannelId)),
	)
}

func emitAdapterDenomUnregisteredEvent(admin address, baseDenom string) {
	chain.Emit(
		AdapterDenomUnregisteredEvent,
		"admin", admin.String(),
		"base_denom", baseDenom,
	)
}
