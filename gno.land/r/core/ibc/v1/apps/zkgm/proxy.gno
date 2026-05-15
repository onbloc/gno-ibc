package zkgm

import (
	"chain/runtime"

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
	gRealm          = runtime.CurrentRealm()
	adminAddressStr string
	receivers       = bptree.NewBPTree32()
)

func AsIBCApp() core.IApp {
	return &App{}
}

func ProxyAddress() address {
	return gRealm.Address()
}

func ProxyPkgPath() string {
	return gRealm.PkgPath()
}

func UpdateImpl(cur realm, r UpdateRequest) {
	caller := runtime.PreviousRealm().PkgPath()
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
	path := runtime.PreviousRealm().PkgPath()
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
	callerPath := runtime.PreviousRealm().PkgPath()
	if callerPath != implPath {
		panic(ufmt.Sprintf("zkgm: only registered impl (%s) can write forward ack, got %s", implPath, callerPath))
	}
	core.WriteAcknowledgement(cross, core.MsgWriteAcknowledgement{
		Packet:          parentPacket,
		Acknowledgement: ack,
	})
}

func BatchSend(cur realm, msg core.MsgBatchSend) core.H256 {
	callerPath := runtime.PreviousRealm().PkgPath()
	if callerPath != implPath && !isTestingBatchSender(callerPath) {
		panic(ufmt.Sprintf("zkgm: only registered impl (%s) can batch send, got %s", implPath, callerPath))
	}
	return core.BatchSend(cross, msg)
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
