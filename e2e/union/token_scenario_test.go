package unione2e

import (
	"fmt"
	"testing"
	"time"
)

func TestTokenScenarioEventHelpers(t *testing.T) {
	ack := make([]byte, 32)
	ack[31] = 1
	if ackTag(ack) != 1 {
		t.Fatal("success ack tag was not decoded")
	}
	var tx indexedTx
	tx.Response.Events = append(tx.Response.Events, struct {
		Type    string `json:"type"`
		PkgPath string `json:"pkg_path"`
		Attrs   []struct {
			Key   string `json:"key"`
			Value string `json:"value"`
		} `json:"attrs"`
	}{Type: "WriteAck", Attrs: []struct {
		Key   string `json:"key"`
		Value string `json:"value"`
	}{{Key: "acknowledgement[0]", Value: "0x01"}, {Key: "acknowledgement[1]", Value: "02"}}})
	if got := txEncodedAttr(tx, "WriteAck", "acknowledgement"); got != "0x0102" {
		t.Fatalf("joined event attr = %q", got)
	}
}

func TestTokenBridgeScenarios(t *testing.T) {
	h := newBridgeHarness(t)

	t.Run("gno_native_to_evm", func(t *testing.T) {
		const amount int64 = 1
		tag := fmt.Sprintf("%09d", time.Now().UnixNano()%1_000_000_000)
		metadata := tokenMetadata{name: "Gno Native " + tag, symbol: "GNO" + tag[len(tag)-3:], decimals: 6}
		var union bridgeOutcome
		if !t.Run("gno_native_to_union_cw20", func(t *testing.T) {
			union = h.gnoNativeToUnion(t, "ugnot", amount, h.cfg.Union.PacketSender, metadata)
			if union.sender < amount || union.recipient != amount {
				t.Fatalf("balance deltas sender=%d recipient=%d, want sender >= %d and recipient=%d", union.sender, union.recipient, amount, amount)
			}
		}) {
			return
		}
		t.Run("union_cw20_to_evm_wrapped_erc20", func(t *testing.T) {
			evm := h.unionCW20ToEVM(t, union.token, amount, h.cfg.EVM.Recipient, metadata)
			if evm.sender != amount || evm.escrow != amount || evm.recipient != amount {
				t.Fatalf("balance deltas = %+v, want all %d", evm, amount)
			}
		})
	})

	t.Run("evm_erc20_to_gno", func(t *testing.T) {
		const amount int64 = 1_000_000_000_000
		tag := fmt.Sprintf("%09d", time.Now().UnixNano()%1_000_000_000)
		metadata := tokenMetadata{name: "EVM Test " + tag, symbol: "EVM" + tag[len(tag)-3:], decimals: 18}
		var union bridgeOutcome
		if !t.Run("evm_erc20_to_union_cw20", func(t *testing.T) {
			union = h.evmERC20ToUnion(t, amount, h.cfg.Union.PacketSender, metadata)
			if union.sender != amount || union.escrow != amount || union.recipient != amount {
				t.Fatalf("balance deltas = %+v, want all %d", union, amount)
			}
		}) {
			return
		}
		t.Run("union_cw20_to_gno_wrapped_grc20", func(t *testing.T) {
			gno := h.unionCW20ToGno(t, union.token, amount, h.cfg.Gno.Sender, metadata)
			if gno.sender != amount || gno.escrow != amount || gno.recipient != 1 {
				t.Fatalf("balance deltas sender=%d escrow=%d recipient=%d, want %d/%d/1 after 10^12 decimal downscaling", gno.sender, gno.escrow, gno.recipient, amount, amount)
			}
		})
	})
}
