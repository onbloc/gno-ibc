// PKGPATH: gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/e2e/scenarios
package scenarios

// Reproduction for "Intent recv dispatches OP_CALL to the proven OnZkgm handler
// with no proof" (local_docs/issue_intent_recv_call_misdispatch.md).
//
// A forged OP_CALL is delivered through the proofless market-maker fast path
// core.IntentPacketRecv (which performs no VerifyMembership). The intent path
// drops the intent flag in dispatchExecute -> executeCall, so the call lands in
// the receiver's proven-call handler OnZkgm with attacker-controlled Sender and
// Calldata, and OnIntentZkgm is never reached.
//
// The mock's OnZkgm increments Calls and records the calldata, while its
// OnIntentZkgm returns an error. The Output block below therefore captures the
// CURRENT (buggy) behavior: the call is dispatched and mock_calls is non-zero.
//
// After a fix (route intent OP_CALL to OnIntentZkgm, or reject it with
// ACK_ERR_ONLY_MAKER), the expected behavior is:
//   - mock_calls 0
//   - the receiver's OnZkgm is never reached on the intent path
// At which point this filetest's Output must be updated to assert that.

import (
	z "gno.land/p/gnoswap/ibc/zkgm"
	core "gno.land/r/core/ibc/v1/core"
	e2e "gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/e2e"
	"gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/mock"
	_ "gno.land/r/gnoswap/ibc/v1/apps/zkgm/v0/loader"
)

const mockReceiverPath = "gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/mock"

func main(cur realm) {
	mock.Reset(cross(cur))
	e2e.RegisterMockLightClient(cross(cur))
	pair := e2e.OpenE2EChannelPair(cross(cur))

	// 1. A bare forged OP_CALL with no membership proof.
	call := z.Call{
		Sender:           []byte("attacker-sender"),
		ContractAddress:  []byte(mockReceiverPath),
		ContractCalldata: []byte("forged-no-proof"),
	}
	callPacket := core.NewPacket(cross(cur), pair.Source, pair.Destination,
		e2e.MustPacketData(cross(cur), e2e.MustCallInstruction(cross(cur), call)), 0, core.Timestamp(0))

	core.IntentPacketRecv(cross(cur),
		core.NewMsgIntentPacketRecv(cross(cur), []core.Packet{callPacket}, nil))

	println("call_mock_calls", mock.Calls(cross(cur)))
	println("call_last_sender", mock.LastSender(cross(cur)))
	println("call_last_calldata", mock.LastCalldata(cross(cur)))

	// 2. The same hole via an OP_BATCH child call (batch on intent reuses
	// executeCall), to confirm the acceptance criterion about batched calls.
	mock.Reset(cross(cur))
	batch := z.Batch{Instructions: []z.Instruction{
		e2e.MustCallInstruction(cross(cur), z.Call{
			Sender:           []byte("attacker-sender"),
			ContractAddress:  []byte(mockReceiverPath),
			ContractCalldata: []byte("forged-batch-call"),
		}),
	}}
	batchPacket := core.NewPacket(cross(cur), pair.Source, pair.Destination,
		e2e.MustPacketData(cross(cur), e2e.MustBatchInstruction(cross(cur), batch)), 0, core.Timestamp(0))

	core.IntentPacketRecv(cross(cur),
		core.NewMsgIntentPacketRecv(cross(cur), []core.Packet{batchPacket}, nil))

	println("batch_mock_calls", mock.Calls(cross(cur)))
	println("batch_last_calldata", mock.LastCalldata(cross(cur)))
}

// Output:
// call_mock_calls 1
// call_last_sender attacker-sender
// call_last_calldata forged-no-proof
// batch_mock_calls 1
// batch_last_calldata forged-batch-call
