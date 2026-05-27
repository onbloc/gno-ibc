package zkgm

import (
	"chain"
	"chain/banker"

	z "gno.land/p/gnoswap/ibc/zkgm"
	"gno.land/p/nt/bptree/v0"
	"gno.land/p/nt/ufmt/v0"
	core "gno.land/r/core/ibc/v1/core"
)

var (
	impl            ZkgmImpl
	implPath        string
	allowedImpls    []string
	paused          bool
	gRealm          realm
	adminAddressStr string
	receivers       = bptree.NewBPTree32()
)

const proxyPkgPath = "gno.land/r/gnoswap/ibc/v1/apps/zkgm"

func AsIBCApp() core.IApp {
	return &App{}
}

func ProxyAddress() address {
	return cachedRealm().Address()
}

func ProxyPkgPath() string {
	return proxyPkgPath
}

func UpdateImpl(cur realm, r UpdateRequest) {
	cacheRealm(cur)
	caller := cur.Previous().PkgPath()
	if !InAllowedImpls(caller) {
		panic("permission denied for prev realm: " + caller)
	}
	if r.AllowedImpls != nil {
		allowedImpls = cloneStrings(r.AllowedImpls)
	}
	if r.Impl != nil {
		impl = r.Impl
		implPath = caller
	}
}

func InAllowedImpls(pkg string) bool {
	if len(allowedImpls) == 0 {
		return true
	}
	for _, allowed := range allowedImpls {
		if allowed == pkg {
			return true
		}
	}
	return false
}

func AllowedImpls() []string {
	return cloneStrings(allowedImpls)
}

func ImplPath() string {
	return implPath
}

func IsPaused() bool {
	return paused
}

func RegisterReceiver(cur realm, receiver z.Zkgmable) {
	cacheRealm(cur)
	path := cur.Previous().PkgPath()
	if updated := receivers.Set(path, receiver); updated {
		panic("zkgm: receiver already registered for " + path)
	}
}

func GetReceiver(path string) z.Zkgmable {
	value, ok := receivers.Get(path)
	if !ok {
		return nil
	}
	return value.(z.Zkgmable)
}

// WriteForwardAck writes the parent packet acknowledgement through core. The
// parent's identity is the full Packet captured in InFlightValue at forward
// dispatch time.
func WriteForwardAck(cur realm, parentPacket core.Packet, ack []byte) {
	cacheRealm(cur)
	requireImplCaller(cur, "write forward ack")

	core.WriteAcknowledgement(cross(cur), core.MsgWriteAcknowledgement{
		Packet:          parentPacket,
		Acknowledgement: ack,
	})
}

func BatchSend(cur realm, msg core.MsgBatchSend) core.H256 {
	cacheRealm(cur)
	callerPath := cur.Previous().PkgPath()
	if callerPath != implPath && !isTestingBatchSender(callerPath) {
		panic(ufmt.Sprintf("zkgm: only registered impl (%s) can batch send, got %s", implPath, callerPath))
	}
	return core.BatchSend(cross(cur), msg)
}

// ReleaseNative transfers `amount` of `denom` from the proxy realm's escrow
// to `recipient`. Only callable by the registered impl or an entry in
// allowedImpls. Used by the impl-side `sendNative` so refunds and releases
// are sourced from where the user's `-send` actually lands.
func ReleaseNative(cur realm, denom string, recipient address, amount int64) {
	cacheRealm(cur)
	requireImplCaller(cur, "release native")

	if amount <= 0 {
		panic("zkgm: ReleaseNative amount must be positive")
	}
	if denom == "" {
		panic("zkgm: ReleaseNative denom must not be empty")
	}
	b := banker.NewBanker(banker.BankerTypeRealmSend, cur)
	b.SendCoins(cur.Address(), recipient, chain.NewCoins(chain.NewCoin(denom, amount)))
}

// requireImplCaller panics unless the caller is the registered impl realm or
// an entry in allowedImpls. Used by impl-only entrypoints that move state or
// funds on behalf of the proxy.
func requireImplCaller(cur realm, action string) {
	callerPath := cur.Previous().PkgPath()
	if callerPath != implPath && (len(allowedImpls) == 0 || !InAllowedImpls(callerPath)) {
		panic(ufmt.Sprintf("zkgm: only registered impl (%s) can %s, got %s", implPath, action, callerPath))
	}
}

func cacheRealm(cur realm) {
	if gRealm == (realm{}) {
		gRealm = cur
	}
}

func cachedRealm() realm {
	if gRealm == (realm{}) {
		panic("zkgm: proxy realm not initialized")
	}
	return gRealm
}

func isTestingBatchSender(pkgPath string) bool {
	return pkgPath == "gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/e2e" ||
		pkgPath == "gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/realcometbls"
}

func cloneStrings(in []string) []string {
	out := make([]string, len(in))
	copy(out, in)
	return out
}
