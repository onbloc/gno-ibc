// PKGPATH: gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/loader
package loader

import (
	zkgm "gno.land/r/onbloc/unionibc/v1/apps/zkgm"
	impl "gno.land/r/onbloc/unionibc/v1/apps/zkgm/v0/impl"
	core "gno.land/r/onbloc/unionibc/v1/core"
)

func main(cur realm) {
	zkgm.UpdateImpl(cross(cur), zkgm.NewUpdateRequest(cross(cur), impl.GetInstance(cross(cur)), []string{
		"gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/loader",
	}))

	parent := core.NewPacket(cross(cur), core.ChannelId(1), core.ChannelId(2), []byte("parent"), 0, core.Timestamp(10))
	child := core.NewPacket(cross(cur), core.ChannelId(3), core.ChannelId(4), []byte("child"), 0, core.Timestamp(20))
	key := zkgm.NewInFlightKey(cross(cur), core.CommitPacket(child))
	value := zkgm.NewInFlightValue(cross(cur), parent)

	zkgm.SetInFlightPacket(cross(cur), key, value)
	_, found := zkgm.PopInFlightPacket(cross(cur), key)
	_, foundAgain := zkgm.PopInFlightPacket(cross(cur), key)

	println("first_pop", found)
	println("second_pop", foundAgain)
	println("inflight_events", "ok")
}

// Output:
// first_pop true
// second_pop false
// inflight_events ok

// Events:
// [
//   {
//     "type": "ZkgmImplUpdated",
//     "attrs": [
//       {
//         "key": "caller_pkg_path",
//         "value": "gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/loader"
//       },
//       {
//         "key": "old_impl_path",
//         "value": ""
//       },
//       {
//         "key": "new_impl_path",
//         "value": "gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/loader"
//       },
//       {
//         "key": "allowed_impls",
//         "value": "gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/loader"
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/unionibc/v1/apps/zkgm"
//   },
//   {
//     "type": "ZkgmForwardInFlightSet",
//     "attrs": [
//       {
//         "key": "packet_hash",
//         "value": "0x2439f86abd6d0bc03451980414231d33137e303f4d896df3e3f69345257d26fa"
//       },
//       {
//         "key": "parent_packet_hash",
//         "value": "0x400840bbb1b30e67f48a6d65ede08523f569da22608f0836efd16bffce384bb8"
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/unionibc/v1/apps/zkgm"
//   },
//   {
//     "type": "ZkgmForwardInFlightPopped",
//     "attrs": [
//       {
//         "key": "packet_hash",
//         "value": "0x2439f86abd6d0bc03451980414231d33137e303f4d896df3e3f69345257d26fa"
//       },
//       {
//         "key": "found",
//         "value": "true"
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/unionibc/v1/apps/zkgm"
//   },
//   {
//     "type": "ZkgmForwardInFlightPopped",
//     "attrs": [
//       {
//         "key": "packet_hash",
//         "value": "0x2439f86abd6d0bc03451980414231d33137e303f4d896df3e3f69345257d26fa"
//       },
//       {
//         "key": "found",
//         "value": "false"
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/unionibc/v1/apps/zkgm"
//   }
// ]
