package transfer

import (
	"testing"

	"gno.land/p/aib/ibc/types"
	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

// Send() is the realm-initiated ICS20 outbound path, gated by hookCaller.
// In tests, cross(cur) makes cur.Previous() inside Send() resolve to this
// package's realm address, so setting hookCaller = cur.Address() authorizes
// the call, and any other address denies it.

// TestSendZeroAmountIsRejected verifies that Send() panics when amount is zero.
func TestSendZeroAmountIsRejected(cur realm, t *testing.T) {
	hookCaller = cur.Address()
	defer func() { hookCaller = address("") }()

	recvPayload := makeTransferPayload("cosmos1s", cur.Address().String(), "uatomzero", "100")
	(&App{}).OnRecvPacket(cur, "07-tendermint-0", "07-tendermint-1", 70, recvPayload)
	voucherDenom := NewDenom("uatomzero", NewHop(PortID, "07-tendermint-1")).IBCDenom()

	uassert.AbortsContains(t, cur, "transfer: amount must be positive", func() {
		Send(cross(cur), "07-tendermint-1", "cosmos1dst", voucherDenom, 0, 9999999, "")
	})
}

// TestSendNegativeAmountIsRejected verifies that Send() panics when amount is negative.
func TestSendNegativeAmountIsRejected(cur realm, t *testing.T) {
	hookCaller = cur.Address()
	defer func() { hookCaller = address("") }()

	recvPayload := makeTransferPayload("cosmos1s", cur.Address().String(), "uatomneg", "100")
	(&App{}).OnRecvPacket(cur, "07-tendermint-0", "07-tendermint-1", 71, recvPayload)
	voucherDenom := NewDenom("uatomneg", NewHop(PortID, "07-tendermint-1")).IBCDenom()

	uassert.AbortsContains(t, cur, "transfer: amount must be positive", func() {
		Send(cross(cur), "07-tendermint-1", "cosmos1dst", voucherDenom, -1, 9999999, "")
	})
}

// TestSendUnauthorizedCallerIsRejected verifies that a caller whose address
// does not match hookCaller cannot initiate a Send().
func TestSendUnauthorizedCallerIsRejected(cur realm, t *testing.T) {
	hookCaller = address(testutils.TestAddress("some-hook-caller"))
	defer func() { hookCaller = address("") }()

	uassert.AbortsContains(t, cur, "transfer: Send: unauthorized caller", func() {
		Send(cross(cur), "07-tendermint-0", "g1receiver", "ibc/HASH", 100, 9999999, "")
	})
}

// TestSendVoucherNotFoundIsRejected verifies that Send() panics when the
// requested IBC denom has no registered voucher token.
func TestSendVoucherNotFoundIsRejected(cur realm, t *testing.T) {
	hookCaller = cur.Address()
	defer func() { hookCaller = address("") }()

	uassert.AbortsContains(t, cur, "voucher denom", func() {
		Send(cross(cur), "07-tendermint-0", "g1receiver",
			"ibc/AABBCCDDEEFF00112233445566778899AABBCCDDEEFF00112233445566778899", 100, 9999999, "")
	})
}

// TestSendPassesAuthCheck verifies that a hookCaller-authorized Send() passes
// the auth guard. The abort here comes from core.SendPacket ("not found"),
// not from the auth check, proving the guard was satisfied.
func TestSendPassesAuthCheck(cur realm, t *testing.T) {
	hookCaller = cur.Address()
	defer func() { hookCaller = address("") }()

	receiver := cur.Address()
	recvPayload := makeTransferPayload("cosmos1s", receiver.String(), "uatomsendauth", "200")
	(&App{}).OnRecvPacket(cur, "07-tendermint-0", "07-tendermint-1", 50, recvPayload)
	voucherDenom := NewDenom("uatomsendauth", NewHop(PortID, "07-tendermint-1")).IBCDenom()

	// Auth passes; core.SendPacket fails because the client is not registered
	// in the unit-test environment.
	uassert.AbortsContains(t, cur, "not found", func() {
		Send(cross(cur), "07-tendermint-0", "cosmos1dst", voucherDenom, 200, 9999999999, "")
	})
}

// TestOnSendPacketAllowsRealmSender verifies the OnSendPacket sender-check
func TestOnSendPacketAllowsRealmSender(cur realm, t *testing.T) {
	realmAddr := address(testutils.TestAddress("realm-sender"))

	// Mint vouchers to realmAddr so OnSendPacket can burn them.
	recvPayload := makeTransferPayload("cosmos1s", realmAddr.String(), "uatomsendgate", "100")
	(&App{}).OnRecvPacket(cur, "07-tendermint-0", "07-tendermint-1", 60, recvPayload)

	voucherDenom := NewDenom("uatomsendgate", NewHop(PortID, "07-tendermint-1")).IBCDenom()
	d, _ := getDenom(voucherDenom)

	// Simulate the state Send() sets up: pending send with sender = realmAddr.
	pendingVoucherSend = &pendingSend{
		sender:       realmAddr.String(),
		sourceClient: "07-tendermint-1",
		denom:        d.Path(),
		amount:       100,
	}
	defer func() { pendingVoucherSend = nil }()

	data := NewFungibleTokenPacketData(d.Path(), "100", realmAddr.String(), "cosmos1dst", "")
	payload := types.Payload{
		SourcePort:      PortID,
		DestinationPort: PortID,
		Version:         V1,
		Encoding:        EncodingProtobuf,
		Value:           data.ProtoMarshal(),
	}

	// Calling OnSendPacket directly (bypassing core). The realm address as
	// Sender differs from any EOA signer, but the pendingVoucherSend guard
	// allows it through.
	err := (&App{}).OnSendPacket(cur, "07-tendermint-1", "07-tendermint-0", 60, payload)
	if err != nil {
		t.Fatalf("realm-initiated send must not fail on sender check: %v", err)
	}
}
