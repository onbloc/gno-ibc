// PKGPATH: gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/loader
package loader

import (
	"chain"
	stdtesting "testing"

	z "gno.land/p/onbloc/ibc/union/zkgm"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	impl "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	core "gno.land/r/onbloc/ibc/union/core"
)

type eventReceiver struct{}

func (r *eventReceiver) OnZkgm(cur realm, env z.CallEnv) error {
	return nil
}

func (r *eventReceiver) OnIntentZkgm(cur realm, env z.IntentCallEnv) error {
	return nil
}

func main(cur realm) {
	zkgm.UpdateImpl(cross(cur), zkgm.NewUpdateRequest(cross(cur), impl.GetInstance(cross(cur)), []string{
		"gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/loader",
	}))

	zkgm.RegisterReceiver(cross(cur), &eventReceiver{})
	stdtesting.IssueCoins(zkgm.ProxyAddress(), chain.NewCoins(chain.NewCoin("ureleaseevent", 9)))
	zkgm.ReleaseNative(cross(cur), "ureleaseevent", address("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm"), 9)

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
//         "value": "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/loader"
//       },
//       {
//         "key": "old_impl_path",
//         "value": ""
//       },
//       {
//         "key": "new_impl_path",
//         "value": "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/loader"
//       },
//       {
//         "key": "allowed_impls",
//         "value": "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/loader"
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
//   },
//   {
//     "type": "ZkgmReceiverRegistered",
//     "attrs": [
//       {
//         "key": "receiver_pkg_path",
//         "value": "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/loader"
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
//   },
//   {
//     "type": "ZkgmNativeReleased",
//     "attrs": [
//       {
//         "key": "caller_pkg_path",
//         "value": "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/loader"
//       },
//       {
//         "key": "denom",
//         "value": "ureleaseevent"
//       },
//       {
//         "key": "recipient",
//         "value": "g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm"
//       },
//       {
//         "key": "amount",
//         "value": "9"
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
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
//     "pkg_path": "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
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
//     "pkg_path": "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
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
//     "pkg_path": "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
//   }
// ]
