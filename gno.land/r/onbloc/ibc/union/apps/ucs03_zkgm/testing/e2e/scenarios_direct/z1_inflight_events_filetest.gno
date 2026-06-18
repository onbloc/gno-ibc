// PKGPATH: gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/e2e/scenarios_direct
package scenarios_direct

import (
	"chain"

	types "gno.land/p/onbloc/ibc/union/types"

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
	zkgm.UpdateImpl(cross(cur), zkgm.NewUpdateRequest(cross(cur), impl.New(cross(cur)), []string{
		"gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/e2e/scenarios_direct",
	}))

	zkgm.RegisterReceiver(cross(cur), &eventReceiver{})
	stdtesting.IssueCoins(zkgm.ProxyAddress(), chain.NewCoins(chain.NewCoin("ureleaseevent", 9)))
	zkgm.ReleaseNative(cross(cur), "ureleaseevent", address("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm"), 9)

	parent := core.NewPacket(types.ChannelId(1), types.ChannelId(2), []byte("parent"), types.Timestamp(10))
	child := core.NewPacket(types.ChannelId(3), types.ChannelId(4), []byte("child"), types.Timestamp(20))
	key := zkgm.NewInFlightKey(cross(cur), types.MustCommit(types.CommitPacket(child)))
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
//         "value": "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/e2e/scenarios_direct"
//       },
//       {
//         "key": "old_impl_path",
//         "value": ""
//       },
//       {
//         "key": "new_impl_path",
//         "value": "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/e2e/scenarios_direct"
//       },
//       {
//         "key": "allowed_impls",
//         "value": "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/e2e/scenarios_direct"
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
//   },
//   {
//     "type": "ZkgmReceiverRegistered",
//     "attrs": [
//       {
//         "key": "receiver_pkg_path",
//         "value": "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/e2e/scenarios_direct"
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
//   },
//   {
//     "type": "ZkgmNativeReleased",
//     "attrs": [
//       {
//         "key": "caller_pkg_path",
//         "value": "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/e2e/scenarios_direct"
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
