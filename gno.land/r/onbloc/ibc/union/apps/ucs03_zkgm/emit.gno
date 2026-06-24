package zkgm

import (
	types "gno.land/p/onbloc/ibc/union/types"
)

// emit.gno exposes the proxy event emitters the injected impl calls so events
// are emitted from the zkgm proxy realm, keeping the app as the stable event
// source across impl upgrades.

func assertProxyRealmEmitter(_ int, rlm realm) {
	if !rlm.IsCurrent() || rlm.PkgPath() != proxyPkgPath {
		panic(ErrEventEmitterWrongRealm)
	}
}

func EmitRecvError(_ int, rlm realm, sourceChannel types.ChannelId, destinationChannel types.ChannelId, reason string) {
	assertProxyRealmEmitter(0, rlm)
	emitRecvError(sourceChannel, destinationChannel, reason)
}
