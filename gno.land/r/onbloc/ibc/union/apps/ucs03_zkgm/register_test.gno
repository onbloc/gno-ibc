package zkgm

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
	z "gno.land/p/onbloc/ibc/union/zkgm"
)

func TestAsIBCApp(t *testing.T) {
	app := AsIBCApp()
	if app == nil {
		t.Fatal("AsIBCApp returned nil")
	}
}

func TestRegisterReceiver(cur realm, t *testing.T) {
	receiver := &dummyReceiver{}
	receiverA := &dummyReceiver{}
	receiverB := &dummyReceiver{}
	replacementA := z.Zkgmable(&dummyReceiver{})
	replacementB := z.Zkgmable(&dummyReceiver{})

	cases := []struct {
		name          string
		registerPaths []string
		receivers     []z.Zkgmable
		wantPaths     []string
		wantReceivers []z.Zkgmable
	}{
		{
			name:          "stores previous realm path",
			registerPaths: []string{"gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/receiver"},
			receivers:     []z.Zkgmable{receiver},
			wantPaths:     []string{"gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/receiver"},
			wantReceivers: []z.Zkgmable{receiver},
		},
		{
			name: "separates previous realm keys",
			registerPaths: []string{
				"gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/receiver_a",
				"gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/receiver_b",
			},
			receivers: []z.Zkgmable{receiverA, receiverB},
			wantPaths: []string{
				"gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/receiver_a",
				"gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/receiver_b",
			},
			wantReceivers: []z.Zkgmable{receiverA, receiverB},
		},
		{
			name: "replaces receiver for same path",
			registerPaths: []string{
				"gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/direct_receiver",
				"gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/direct_receiver",
			},
			receivers:     []z.Zkgmable{replacementA, replacementB},
			wantPaths:     []string{"gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/direct_receiver"},
			wantReceivers: []z.Zkgmable{replacementB},
		},
	}

	for _, tc := range cases {
		resetZkgmForTest()
		for i, path := range tc.registerPaths {
			testing.SetRealm(testing.NewCodeRealm(path))
			RegisterReceiver(cross(cur), tc.receivers[i])
		}
		for i, path := range tc.wantPaths {
			got, ok := store.GetReceiver(path)
			uassert.True(t, ok)
			uassert.True(t, got == tc.wantReceivers[i])
		}
	}
}
