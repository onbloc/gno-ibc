package zkgm

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func TestRegisterReceiverStoresPreviousRealmPath(cur realm, t *testing.T) {
	resetZkgmForTest()

	const receiverPath = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/receiver"
	receiver := &dummyReceiver{}

	testing.SetRealm(testing.NewCodeRealm(receiverPath))
	RegisterReceiver(cross(cur), receiver)

	got, ok := store.GetReceiver(receiverPath)
	uassert.True(t, ok)
	uassert.True(t, got == receiver)
}

func TestRegisterReceiverSeparatesPreviousRealmKeys(cur realm, t *testing.T) {
	resetZkgmForTest()

	const receiverPathA = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/receiver_a"
	const receiverPathB = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/receiver_b"
	receiverA := &dummyReceiver{}
	receiverB := &dummyReceiver{}

	testing.SetRealm(testing.NewCodeRealm(receiverPathA))
	RegisterReceiver(cross(cur), receiverA)
	testing.SetRealm(testing.NewCodeRealm(receiverPathB))
	RegisterReceiver(cross(cur), receiverB)

	gotA, okA := store.GetReceiver(receiverPathA)
	gotB, okB := store.GetReceiver(receiverPathB)
	uassert.True(t, okA)
	uassert.True(t, okB)
	uassert.True(t, gotA == receiverA)
	uassert.True(t, gotB == receiverB)
}
