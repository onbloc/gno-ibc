// PKGPATH: gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/upgrade
package upgrade

import (
	stdtesting "testing"

	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	upgradeimpl "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/upgradeimpl"
	core "gno.land/r/onbloc/ibc/union/core"
)

func main(cur realm) {
	oldImpl := zkgm.ProxyPkgPath() + "/testing/inflight-old"
	newImpl := zkgm.ProxyPkgPath() + "/testing/inflight-new"
	parent := core.NewPacket(cross(cur), core.ChannelId(10), core.ChannelId(11), []byte("parent"), 0, core.Timestamp(100))
	child := core.NewPacket(cross(cur), core.ChannelId(12), core.ChannelId(13), []byte("child"), 0, core.Timestamp(200))
	key := zkgm.NewInFlightKey(cross(cur), core.CommitPacket(child))
	value := zkgm.NewInFlightValue(cross(cur), parent)

	println("[SCENARIO] 1. record in-flight packet before upgrade")
	stdtesting.SetRealm(stdtesting.NewCodeRealm(oldImpl))
	zkgm.UpdateImpl(cross(cur), zkgm.NewUpdateRequest(cross(cur), upgradeimpl.New(cross(cur), "old"), []string{
		oldImpl,
		newImpl,
	}))
	zkgm.SetInFlightPacket(cross(cur), key, value)
	println("[EXPECTED] impl_path_before", zkgm.ImplPath())

	println("")
	println("[SCENARIO] 2. upgrade implementation")
	stdtesting.SetRealm(stdtesting.NewCodeRealm(newImpl))
	zkgm.UpdateImpl(cross(cur), zkgm.NewUpdateRequest(cross(cur), upgradeimpl.New(cross(cur), "new"), []string{
		newImpl,
	}))
	println("[EXPECTED] impl_path_after", zkgm.ImplPath())

	println("")
	println("[SCENARIO] 3. complete in-flight packet after upgrade")
	popped, popFound := zkgm.PopInFlightPacket(cross(cur), key)
	_, foundAgain := zkgm.PopInFlightPacket(cross(cur), key)
	println("[EXPECTED] pop_after_upgrade", popFound)
	println("[EXPECTED] parent_data", string(popped.ParentPacket.Data))
	println("[EXPECTED] second_pop", foundAgain)
}

// Output:
// [SCENARIO] 1. record in-flight packet before upgrade
// [EXPECTED] impl_path_before gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/inflight-old
//
// [SCENARIO] 2. upgrade implementation
// [EXPECTED] impl_path_after gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/inflight-new
//
// [SCENARIO] 3. complete in-flight packet after upgrade
// [EXPECTED] pop_after_upgrade true
// [EXPECTED] parent_data parent
// [EXPECTED] second_pop false
