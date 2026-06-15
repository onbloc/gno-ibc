package zkgm

import (
	"chain"
	"chain/banker"
	"strings"

	"gno.land/p/nt/bptree/v0"
	"gno.land/p/nt/ufmt/v0"
	z "gno.land/p/onbloc/ibc/zkgm"
	core "gno.land/r/onbloc/ibc/core"
)

var (
	impl          ZkgmImpl
	implPath      string
	allowedImpls  []string
	bootstrapped  bool
	paused        bool
	gRealmAddress address
	gRealmSet     bool
	receivers     = bptree.NewBPTree32()
)

const proxyPkgPath = "gno.land/r/onbloc/ibc/apps/ucs03_zkgm"

// productionLoaderPath is the only loader allowed to re-fetch the impl singleton
// after bootstrap. It is the trust anchor for impl.GetInstance.
const productionLoaderPath = proxyPkgPath + "/v1/loader"

func AsIBCApp() core.IApp {
	return &App{}
}

func RegisterCoreApp(cur realm) {
	core.RegisterApp(cross(cur), AsIBCApp())
}

func ProxyAddress() address {
	if !gRealmSet {
		panic("zkgm: proxy realm not initialized")
	}
	return gRealmAddress
}

func ProxyPkgPath() string {
	return proxyPkgPath
}

func ProductionLoaderPath() string {
	return productionLoaderPath
}

func UpdateImpl(cur realm, r UpdateRequest) {
	cacheRealm(cur)
	caller := cur.Previous().PkgPath()
	oldImplPath := implPath
	if implPath == "" && len(allowedImpls) == 0 {
		requireBootstrapLoaderRealm(caller)
		if r.Impl == nil {
			panic("zkgm: bootstrap UpdateImpl must install an impl")
		}
		if caller == productionLoaderPath && len(r.AllowedImpls) == 0 {
			panic("zkgm: production loader bootstrap must install allowed impls")
		}
	} else if !isAuthorizedImpl(caller) {
		panic("permission denied for prev realm: " + caller)
	}
	if r.AllowedImpls != nil {
		allowedImpls = cloneStrings(r.AllowedImpls)
	}
	if r.Impl != nil {
		impl = r.Impl
		implPath = caller
		bootstrapped = true
	}
	emitZkgmImplUpdatedEvent(caller, oldImplPath, implPath, allowedImpls)
}

func InAllowedImpls(pkg string) bool {
	for _, allowed := range allowedImpls {
		if allowed == pkg {
			return true
		}
	}
	return false
}

func isAuthorizedImpl(caller string) bool {
	return caller != "" && (caller == implPath || InAllowedImpls(caller))
}

// First install is limited to subpackages of the ZKGM proxy realm. The
// onbloc/unionibc namespace is governance-granted, so the namespace owner
// controls which ZKGM subpackages can be deployed.
func isBootstrapCaller(caller string) bool {
	return strings.HasPrefix(caller, proxyPkgPath+"/")
}

func requireBootstrapLoaderRealm(caller string) {
	if !isBootstrapCaller(caller) {
		panic("zkgm: bootstrap not permitted for caller: " + caller)
	}
}

func AllowedImpls() []string {
	return cloneStrings(allowedImpls)
}

func ImplPath() string {
	return implPath
}

func Bootstrapped() bool {
	return bootstrapped
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
	emitZkgmReceiverRegisteredEvent(path)
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
	requireImplRealm(cur, "write forward ack")

	core.WriteAcknowledgement(cross(cur), core.NewMsgWriteAcknowledgement(cross(cur), parentPacket, ack))
}

func BatchSend(cur realm, msg core.MsgBatchSend) core.H256 {
	cacheRealm(cur)
	requireImplRealm(cur, "batch send")
	return core.BatchSend(cross(cur), msg)
}

// ReleaseNative transfers amount of denom from the proxy realm's escrow to
// recipient. It may only be called by the registered implementation realm or an
// allowed implementation realm.
//
// ReleaseNative is used by implementation-side sendNative calls so refunds and
// releases are sourced from the escrow where the user's -send funds land.
func ReleaseNative(cur realm, denom string, recipient address, amount int64) {
	cacheRealm(cur)
	requireImplRealm(cur, "release native")

	if amount <= 0 {
		panic("zkgm: ReleaseNative amount must be positive")
	}
	if denom == "" {
		panic("zkgm: ReleaseNative denom must not be empty")
	}
	b := banker.NewBanker(banker.BankerTypeRealmSend, cur)
	b.SendCoins(cur.Address(), recipient, chain.NewCoins(chain.NewCoin(denom, amount)))
	emitZkgmNativeReleasedEvent(cur.Previous().PkgPath(), denom, recipient, amount)
}

// requireImplRealm panics unless the caller is the registered implementation
// realm or an allowed implementation realm.
func requireImplRealm(cur realm, action string) {
	callerPath := cur.Previous().PkgPath()
	if !isAuthorizedImpl(callerPath) {
		panic(ufmt.Sprintf("zkgm: caller is not an authorized impl for %s: %s", action, callerPath))
	}
}

// cacheRealm records the proxy realm address for later use.
//
// Realm values are tied to a call frame and cannot be persisted across phases.
// On the first proxy boundary crossing, this function extracts Address() from
// cur and stores it in package-level state so downstream code can access the
// proxy realm address without retaining the original realm value.
func cacheRealm(cur realm) {
	if !gRealmSet {
		gRealmAddress = cur.Address()
		gRealmSet = true
	}
}

func cloneStrings(in []string) []string {
	out := make([]string, len(in))
	copy(out, in)
	return out
}
