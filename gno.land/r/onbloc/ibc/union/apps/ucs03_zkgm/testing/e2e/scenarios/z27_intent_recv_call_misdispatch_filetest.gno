// PKGPATH: gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/e2e/scenarios
package scenarios

// Regression for "Intent recv dispatches OP_CALL to the proven OnZkgm handler
// with no proof" (local_docs/issue_intent_recv_call_misdispatch.md).
//
// A forged OP_CALL is delivered through the proofless market-maker fast path
// core.IntentPacketRecv, which performs no VerifyMembership. Intent calls must
// fail closed with ACK_ERR_ONLY_MAKER so IntentRecv reverts and the call waits
// for proven recv.
//
// The mock's OnZkgm increments Calls and records calldata. This test asserts
// that bare OP_CALL and batched OP_CALL both revert before reaching OnZkgm.

import (
	types "gno.land/p/onbloc/ibc/union/types"

	z "gno.land/p/onbloc/ibc/union/zkgm"
	e2e "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/e2e"
	"gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/mock"
	impl "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	core "gno.land/r/onbloc/ibc/union/core"
)

const mockReceiverPath = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/mock"

func intentRecvReverted(cur realm, packet types.Packet) (reverted bool) {
	p := revive(func() {
		core.IntentPacketRecv(cross(cur),
			types.NewMsgIntentPacketRecv([]types.Packet{packet}, [][]byte{nil}, address("")))
	})
	return p != nil
}

func main(cur realm) {
	impl.Register(cross(cur))
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
		e2e.MustPacketData(cross(cur), e2e.MustCallInstruction(cross(cur), call)), types.Timestamp(0))

	println("call_reverted", intentRecvReverted(cur, callPacket))
	println("call_mock_calls", mock.Calls(cross(cur)))

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
		e2e.MustPacketData(cross(cur), e2e.MustBatchInstruction(cross(cur), batch)), types.Timestamp(0))

	println("batch_reverted", intentRecvReverted(cur, batchPacket))
	println("batch_mock_calls", mock.Calls(cross(cur)))
}

// Output:
// call_reverted true
// call_mock_calls 0
// batch_reverted true
// batch_mock_calls 0
