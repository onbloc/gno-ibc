package transfer

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func TestForwardCorrID(t *testing.T) {
	uassert.Equal(t, "07-tendermint-0/0000000000000005", forwardCorrID("07-tendermint-0", 5))
	uassert.NotEqual(t, forwardCorrID("07-tendermint-0", 5), forwardCorrID("07-tendermint-0", 6))
	uassert.NotEqual(t, forwardCorrID("07-tendermint-0", 5), forwardCorrID("07-tendermint-1", 5))
}

func TestPendingForwardRoundTrip(cur realm, t *testing.T) {
	pendingForwards.Remove(forwardCorrID("07-tendermint-0", 1))

	corrID := forwardCorrID("07-tendermint-0", 1)
	_, found := getPendingForward(corrID)
	uassert.False(t, found)

	want := pendingForward{
		DestinationClient: "07-tendermint-2",
		Sequence:          1,
		VoucherDenom:      "ibc/AAAA",
		Amount:            100,
	}
	pendingForwards.Set(corrID, want)

	got, found := getPendingForward(corrID)
	uassert.True(t, found)
	uassert.Equal(t, want.DestinationClient, got.DestinationClient)
	uassert.Equal(t, want.Sequence, got.Sequence)
	uassert.Equal(t, want.VoucherDenom, got.VoucherDenom)
	uassert.Equal(t, want.Amount, got.Amount)

	deletePendingForward(corrID)
	_, found = getPendingForward(corrID)
	uassert.False(t, found)
}
