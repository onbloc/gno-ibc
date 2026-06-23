package types

import (
	"testing"

	"gno.land/p/onbloc/access/manager"
)

func TestRelayerSelectors(t *testing.T) {
	tests := []struct {
		name                 string
		wantCount            int
		wantSelectorsPresent []manager.Selector
	}{
		{
			name:      "returns all 18 selectors",
			wantCount: 18,
			wantSelectorsPresent: []manager.Selector{
				RelayerSelectorRegisterClient,
				RelayerSelectorCreateClient,
				RelayerSelectorUpdateClient,
				RelayerSelectorMisbehaviour,
				RelayerSelectorConnectionOpenInit,
				RelayerSelectorConnectionOpenTry,
				RelayerSelectorConnectionOpenAck,
				RelayerSelectorConnectionOpenConfirm,
				RelayerSelectorChannelOpenInit,
				RelayerSelectorChannelOpenTry,
				RelayerSelectorChannelOpenAck,
				RelayerSelectorChannelOpenConfirm,
				RelayerSelectorBatchSend,
				RelayerSelectorBatchAcks,
				RelayerSelectorPacketRecv,
				RelayerSelectorIntentPacketRecv,
				RelayerSelectorPacketAck,
				RelayerSelectorPacketTimeout,
			},
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := RelayerSelectors()

			// Verify length
			if len(got) != tc.wantCount {
				t.Fatalf("length: got %d want %d", len(got), tc.wantCount)
			}

			// Verify each expected selector is present
			selectorMap := make(map[manager.Selector]bool)
			for _, s := range got {
				selectorMap[s] = true
			}

			for _, want := range tc.wantSelectorsPresent {
				if !selectorMap[want] {
					t.Fatalf("missing selector: %s", want)
				}
			}

			// Verify order matches declaration order
			expectedOrder := []manager.Selector{
				RelayerSelectorRegisterClient,
				RelayerSelectorCreateClient,
				RelayerSelectorUpdateClient,
				RelayerSelectorMisbehaviour,
				RelayerSelectorConnectionOpenInit,
				RelayerSelectorConnectionOpenTry,
				RelayerSelectorConnectionOpenAck,
				RelayerSelectorConnectionOpenConfirm,
				RelayerSelectorChannelOpenInit,
				RelayerSelectorChannelOpenTry,
				RelayerSelectorChannelOpenAck,
				RelayerSelectorChannelOpenConfirm,
				RelayerSelectorBatchSend,
				RelayerSelectorBatchAcks,
				RelayerSelectorPacketRecv,
				RelayerSelectorIntentPacketRecv,
				RelayerSelectorPacketAck,
				RelayerSelectorPacketTimeout,
			}
			for i, want := range expectedOrder {
				if got[i] != want {
					t.Fatalf("order mismatch at index %d: got %s want %s", i, got[i], want)
				}
			}
		})
	}
}
