package ics20zkgm_adapter

import (
	"testing"

	aibtypes "gno.land/p/aib/ibc/types"
	"gno.land/p/nt/uassert/v0"
	"gno.land/r/aib/ibc/apps/transfer"
)

// testPayload builds a minimal valid transfer.Payload for a mint-path recv.
func testPayload(baseDenom, amount, sender, receiver, memo string) aibtypes.Payload {
	data := transfer.NewFungibleTokenPacketData(baseDenom, amount, sender, receiver, memo)
	return aibtypes.Payload{
		SourcePort:      transfer.PortID,
		DestinationPort: transfer.PortID,
		Version:         transfer.V1,
		Encoding:        transfer.EncodingProtobuf,
		Value:           data.ProtoMarshal(),
	}
}

func TestOnTransferRecvNoMemoIsNoop(cur realm, t *testing.T) {
	testStore = newMockStore()
	impl := newTestImpl()

	data := transfer.NewFungibleTokenPacketData("uatom-noop", "100", "cosmos1sender", cur.Address().String(), "")
	err := impl.OnTransferRecv(0, cur, fwdSourceClient, 1, data, testMintDenom("uatom-noop"))
	uassert.NoError(t, err)
}

func TestOnTransferRecvUnrelatedMemoIsNoop(cur realm, t *testing.T) {
	testStore = newMockStore()
	impl := newTestImpl()

	data := transfer.NewFungibleTokenPacketData("uatom-unrelated", "100", "cosmos1sender", cur.Address().String(), `{"wasm":{"contract":"g1..."}}`)
	err := impl.OnTransferRecv(0, cur, fwdSourceClient, 2, data, testMintDenom("uatom-unrelated"))
	uassert.NoError(t, err)
}

func TestOnTransferRecvReceiverMismatchIsRejected(cur realm, t *testing.T) {
	testStore = newMockStore()
	impl := newTestImpl()

	otherAddr := testAddress("some-other-receiver")
	data := transfer.NewFungibleTokenPacketData("uatom-mismatch", "100", "cosmos1sender", otherAddr.String(), fwdForwardMemo)
	err := impl.OnTransferRecv(0, cur, fwdSourceClient, 3, data, testMintDenom("uatom-mismatch"))
	uassert.ErrorContains(t, err, errReceiverNotAdapter)
}

func TestOnTransferRecvUnregisteredDenomIsRejected(cur realm, t *testing.T) {
	testStore = newMockStore()
	impl := newTestImpl()

	data := transfer.NewFungibleTokenPacketData("uatom-unregistered", "100", "cosmos1sender", cur.Address().String(), fwdForwardMemo)
	err := impl.OnTransferRecv(0, cur, fwdSourceClient, 4, data, testMintDenom("uatom-unregistered"))
	uassert.ErrorContains(t, err, errDenomNotRegistered)
}

func TestOnTransferRecvInvalidAmountIsRejected(cur realm, t *testing.T) {
	testStore = newMockStore()
	testStore.SetDenomConfig(0, cur, "uatom-badamount", testDenomConfig())
	impl := newTestImpl()

	data := transfer.NewFungibleTokenPacketData("uatom-badamount", "not-a-number", "cosmos1sender", cur.Address().String(), fwdForwardMemo)
	err := impl.OnTransferRecv(0, cur, fwdSourceClient, 5, data, testMintDenom("uatom-badamount"))
	uassert.ErrorContains(t, err, errInvalidAmount)
}

func TestOnTransferRecvInvalidMemoReceiverIsRejected(cur realm, t *testing.T) {
	testStore = newMockStore()
	testStore.SetDenomConfig(0, cur, "uatom-badreceiver", testDenomConfig())
	impl := newTestImpl()

	data := transfer.NewFungibleTokenPacketData("uatom-badreceiver", "100", "cosmos1sender", cur.Address().String(), `{"forward":{"receiver":"not-hex-zz"}}`)
	err := impl.OnTransferRecv(0, cur, fwdSourceClient, 6, data, testMintDenom("uatom-badreceiver"))
	uassert.ErrorContains(t, err, errInvalidReceiver)
}

// TestOnTransferRecvHappyPathReachesZkgmSend verifies that, given a fully
// valid setup (voucher actually minted to this adapter, denom registered),
// OnTransferRecv gets all the way through memo parsing, validation,
// VoucherApprove, and TokenOrderV2 construction, and actually calls
// zkgm.Send. There's no registered zkgm impl in this unit-test realm, so
// zkgm.Send panics on mustGetImpl() -- proving we reached it, the same way
// apps/transfer's own TestSendPassesAuthCheck proves its auth guard passed
// by letting the call reach core.SendPacket's "not found" failure.
func TestOnTransferRecvHappyPathReachesZkgmSend(cur realm, t *testing.T) {
	const baseDenom = "uatom-happy"

	testStore = newMockStore()
	testStore.SetDenomConfig(0, cur, baseDenom, testDenomConfig())
	impl := newTestImpl()

	// Actually mint the voucher to this adapter (cur.Address()), matching
	// what apps/transfer.OnRecvPacket's mint path does, so VoucherApprove
	// has a real voucher to approve.
	payload := testPayload(baseDenom, "100", "cosmos1sender", cur.Address().String(), fwdForwardMemo)
	recvResult := transfer.NewApp().OnRecvPacket(cross(cur), fwdSourceClient, fwdDestClient, 7, payload)
	if recvResult.Status != aibtypes.PacketStatus_Success {
		t.Fatalf("setup: mint recv must succeed, got status=%v", recvResult.Status)
	}

	data := transfer.NewFungibleTokenPacketData(baseDenom, "100", "cosmos1sender", cur.Address().String(), fwdForwardMemo)
	uassert.AbortsWithMessage(t, cur, "implementation not installed", func(cur realm) {
		impl.OnTransferRecv(0, cur, fwdSourceClient, 8, data, testMintDenom(baseDenom))
	})
}
