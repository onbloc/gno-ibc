package transfer

import (
	"errors"
	"testing"

	"gno.land/p/aib/ibc/types"
	"gno.land/p/nt/testutils/v0"
	"chain"
)

// dummyHook is a test-only TransferHook implementation.
type dummyHook struct {
	addr   address
	called bool
	retErr error
}

func (h *dummyHook) Address() address { return h.addr }
func (h *dummyHook) OnTransferRecv(_ realm, _ FungibleTokenPacketData, _ Denom) error {
	h.called = true
	return h.retErr
}

// makeTransferPayload builds a minimal valid transfer Payload.
func makeTransferPayload(sender, receiver, denom, amount string) types.Payload {
	data := NewFungibleTokenPacketData(denom, amount, sender, receiver, "")
	return types.Payload{
		SourcePort:      PortID,
		DestinationPort: PortID,
		Version:         V1,
		Encoding:        EncodingProtobuf,
		Value:           data.ProtoMarshal(),
	}
}

// TestHookCalledOnMintPath verifies that the registered hook fires after a
// successful voucher mint (sender chain is source → mint path).
func TestHookCalledOnMintPath(cur realm, t *testing.T) {
	h := &dummyHook{}
	hook = h
	hookCaller = address("")
	defer func() { hook = nil }()

	receiver := address(testutils.TestAddress("hook-called-recv"))
	payload := makeTransferPayload("cosmos1sender", receiver.String(), "uatom-hook-called", "50")

	result := (&App{}).OnRecvPacket(cur, "07-tendermint-0", "07-tendermint-1", 1, payload)
	if result.Status != types.PacketStatus_Success {
		t.Fatalf("mint recv must succeed: status=%v", result.Status)
	}
	if !h.called {
		t.Fatal("hook must be called on the mint path")
	}
}

// TestHookNotCalledOnUnescrowPath verifies that the registered hook does NOT
// fire when the receiver chain is the source (unescrow path — no new liquidity).
func TestHookNotCalledOnUnescrowPath(cur realm, t *testing.T) {
	h := &dummyHook{}
	hook = h
	hookCaller = address("")
	defer func() { hook = nil }()

	const srcClient = "07-tendermint-0"
	const dstClient = "07-tendermint-1"
	baseDenom := "unescrowtest"

	// The packet denom has the source prefix, triggering the unescrow path.
	// The receiver chain is the origin, so we must have the coin escrowed.
	testing.IssueCoins(cur.Address(), chain.NewCoins(chain.NewCoin(baseDenom, 75)))
	addEscrowForDenom(chain.NewCoin(baseDenom, 75))

	packetDenom := "transfer/" + srcClient + "/" + baseDenom
	receiver := address(testutils.TestAddress("hook-unescrow-recv"))
	payload := makeTransferPayload("cosmos1sender", receiver.String(), packetDenom, "75")

	result := (&App{}).OnRecvPacket(cur, srcClient, dstClient, 2, payload)
	if result.Status != types.PacketStatus_Success {
		t.Fatalf("unescrow recv must succeed: status=%v", result.Status)
	}
	if h.called {
		t.Fatal("hook must NOT be called on the unescrow path")
	}
}

// TestHookErrorReturnsFailureAck verifies that a hook returning an error causes
// OnRecvPacket to return a failure result (not panic), so the source chain
// receives an acknowledgement and can refund the sender.
func TestHookErrorReturnsFailureAck(cur realm, t *testing.T) {
	h := &dummyHook{retErr: errors.New("hook deliberately failed")}
	hook = h
	hookCaller = address("")
	defer func() { hook = nil }()

	receiver := address(testutils.TestAddress("hook-err-recv"))
	payload := makeTransferPayload("cosmos1sender", receiver.String(), "uatom-hook-err", "50")

	result := (&App{}).OnRecvPacket(cur, "07-tendermint-0", "07-tendermint-1", 3, payload)
	if result.Status != types.PacketStatus_Failure {
		t.Fatalf("hook error must produce failure result, got status=%v", result.Status)
	}
}

// TestHookErrorLeavesNoMintedVoucher verifies that when a hook rejects a packet,
// the voucher tokens minted before the hook call are burned back, leaving the
// receiver with a zero balance.
func TestHookErrorLeavesNoMintedVoucher(cur realm, t *testing.T) {
	h := &dummyHook{retErr: errors.New("hook deliberately failed")}
	hook = h
	hookCaller = address("")
	defer func() { hook = nil }()

	receiver := address(testutils.TestAddress("hook-no-voucher-recv"))
	payload := makeTransferPayload("cosmos1sender", receiver.String(), "uatom-hook-no-voucher", "50")

	(&App{}).OnRecvPacket(cur, "07-tendermint-0", "07-tendermint-1", 4, payload)

	voucherDenom := NewDenom("uatom-hook-no-voucher", NewHop(PortID, "07-tendermint-1")).IBCDenom()
	bal := VoucherBalanceOf(voucherDenom, receiver)
	if bal != 0 {
		t.Fatalf("receiver must have zero voucher balance after hook rejection, got %d", bal)
	}
}
