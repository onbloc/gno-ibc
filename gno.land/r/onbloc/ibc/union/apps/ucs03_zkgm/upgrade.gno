package zkgm

var (
	impl         IApp    = nil
	proxyAddress address = ""
)

func init(cur realm) {
	proxyAddress = cur.Address()
}

func ProxyAddress() address {
	return proxyAddress
}

// UpdateImpl installs or re-points the implementation following the bootstrap
// and steady-state tiers of the trust model.
func UpdateImpl(cur realm, target IApp) {
	requireCanCall(0, cur, SelectorUpdateImpl)

	if target == nil {
		panic("zkgm: impl cannot be nil")
	}

	impl = target
}
