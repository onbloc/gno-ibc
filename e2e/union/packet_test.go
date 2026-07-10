package unione2e

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"strconv"
	"strings"
	"testing"
	"time"
)

type indexedTx struct {
	Hash        string `json:"hash"`
	BlockHeight int64  `json:"block_height"`
	Response    struct {
		Events []struct {
			Type    string `json:"type"`
			PkgPath string `json:"pkg_path"`
			Attrs   []struct {
				Key   string `json:"key"`
				Value string `json:"value"`
			} `json:"attrs"`
		} `json:"events"`
	} `json:"response"`
}

func TestPacketPathCreated(t *testing.T) {
	cfg := loadConfig()
	if !cfg.RunPacketTests {
		t.Skip("set RUN_PACKET_TESTS=1 after starting gno-whitelist and Voyager")
	}

	clients, err := queryUnionIBCClients(cfg.UnionREST)
	if err != nil {
		t.Fatalf("query Union IBC clients: %v", err)
	}
	if len(clients) == 0 {
		t.Fatal("no Union IBC clients found")
	}
	t.Logf("Union clients: %+v", clients)

	requireGnoQEvalNonEmpty(t, cfg, "Gno connection "+cfg.GnoPacketConnectionID, fmt.Sprintf("gno.land/r/onbloc/ibc/union/core.QueryConnection(%s)", cfg.GnoPacketConnectionID))
	requireGnoQEvalNonEmpty(t, cfg, "Gno channel "+cfg.GnoPacketChannelID, fmt.Sprintf("gno.land/r/onbloc/ibc/union/core.QueryChannel(%s)", cfg.GnoPacketChannelID))
}

func TestGnoToUnionPacketRelay(t *testing.T) {
	cfg := loadConfig()
	if !cfg.RunPacketTests {
		t.Skip("set RUN_PACKET_TESTS=1 after Voyager creates clients/channels")
	}

	req := gnoTransferRequest{
		ChannelID:  cfg.GnoPacketChannelID,
		OperandHex: os.Getenv("GNO_PACKET_OPERAND_HEX"),
		SendCoins:  os.Getenv("GNO_PACKET_SEND_COINS"),
		SaltHex:    os.Getenv("GNO_PACKET_SALT_HEX"),
	}
	if req.OperandHex == "" {
		t.Skip("set pre-encoded GNO_PACKET_OPERAND_HEX to broadcast SendRaw")
	}
	requirePacketSetup(t, cfg)

	var before int64
	sender, denom := os.Getenv("GNO_SENDER_ADDR"), os.Getenv("GNO_BALANCE_DENOM")
	if sender != "" && denom != "" {
		before = queryGnoBalance(t, cfg, sender, denom)
	}

	out := transferOnGno(t, cfg, req)
	t.Logf("Gno SendRaw output:\n%s", out)

	packetSend := waitForGnoEvent(t, cfg.GnoIndexer, "PacketSend", map[string]string{"source_channel_id": req.ChannelID})
	packetHash := txAttr(packetSend, "PacketSend", "packet_hash")
	if packetHash == "" {
		t.Fatalf("PacketSend event missing packet_hash: %+v", packetSend)
	}
	if got := txAttr(packetSend, "PacketSend", "source_channel_id"); got != "" && got != req.ChannelID {
		t.Fatalf("PacketSend source_channel_id = %s, want %s", got, req.ChannelID)
	}
	if got := txAttr(packetSend, "PacketSend", "destination_channel_id"); got != "" && got != cfg.UnionPacketChannelID {
		t.Fatalf("PacketSend destination_channel_id = %s, want %s", got, cfg.UnionPacketChannelID)
	}

	enqueueGnoBlock(t, cfg, packetSend.BlockHeight)
	waitVoyagerReadyEmpty(t, cfg)

	packetRecv := waitForUnionEvent(t, cfg, "wasm-packet_recv", packetHash)
	writeAck := waitForUnionEvent(t, cfg, "wasm-write_ack", packetHash)
	t.Logf("Union packet recv tx %s at height %d; write_ack tx %s at height %d", packetRecv.Hash, packetRecv.Height, writeAck.Hash, writeAck.Height)

	enqueueUnionBlock(t, cfg, writeAck.Height)
	waitVoyagerReadyEmpty(t, cfg)

	ack := waitForAcknowledgement(t, cfg, packetHash)
	if ack.BlockHeight <= packetSend.BlockHeight {
		t.Fatalf("PacketAck height %d must be after PacketSend height %d", ack.BlockHeight, packetSend.BlockHeight)
	}
	requireNoVoyagerFailed(t, cfg)
	t.Logf("relayed packet hash %s, ack tx %s at height %d", packetHash, ack.Hash, ack.BlockHeight)

	if sender != "" && denom != "" {
		amount := amountFromCoins(req.SendCoins, denom)
		after := queryGnoBalance(t, cfg, sender, denom)
		if amount > 0 && after > before-amount {
			t.Fatalf("Gno balance did not decrease enough: before=%d after=%d sent=%d%s", before, after, amount, denom)
		}
		t.Logf("Gno balance: before=%d after=%d denom=%s", before, after, denom)
	}
}

func requirePacketSetup(t *testing.T, cfg config) {
	t.Helper()
	checkGnoIndexerReady(t, cfg)
	checkUnionReady(t, cfg)
	requireGnoQEvalNonEmpty(t, cfg, "Gno connection "+cfg.GnoPacketConnectionID, fmt.Sprintf("gno.land/r/onbloc/ibc/union/core.QueryConnection(%s)", cfg.GnoPacketConnectionID))
	requireGnoQEvalNonEmpty(t, cfg, "Gno channel "+cfg.GnoPacketChannelID, fmt.Sprintf("gno.land/r/onbloc/ibc/union/core.QueryChannel(%s)", cfg.GnoPacketChannelID))
	requireNoVoyagerFailed(t, cfg)
}

func waitForUnionEvent(t *testing.T, cfg config, eventType, packetHash string) UnionTx {
	t.Helper()
	deadline := time.Now().Add(2 * time.Minute)
	var last error
	for time.Now().Before(deadline) {
		txs, err := queryUnionTxs(cfg.UnionContainer, eventType, packetHash, 3)
		if err == nil && len(txs) > 0 {
			return txs[0]
		}
		last = err
		time.Sleep(time.Second)
	}
	t.Fatalf("Union event %s packet_hash=%s not found: %v\nvoyager stats:\n%s\nvoyager failed:\n%s", eventType, packetHash, last, voyagerQueueStats(t, cfg), voyagerQueryFailed(t, cfg))
	return UnionTx{}
}

func TestUnionToGnoPacketRelay(t *testing.T) {
	cfg := loadConfig()
	if !cfg.RunPacketTests {
		t.Skip("set RUN_PACKET_TESTS=1 after Voyager creates clients/channels")
	}
	packetHash := os.Getenv("UNION_TO_GNO_PACKET_HASH")
	if packetHash == "" {
		t.Skip("set UNION_TO_GNO_PACKET_HASH after broadcasting a Union packet")
	}

	tx := waitForGnoEvent(t, cfg.GnoIndexer, "PacketRecv", map[string]string{"packet_hash": packetHash})
	t.Logf("Gno PacketRecv tx %s at height %d", tx.Hash, tx.BlockHeight)
}

func TestVoucherTokenCreation(t *testing.T) {
	cfg := loadConfig()
	if !cfg.RunPacketTests {
		t.Skip("set RUN_PACKET_TESTS=1 after Voyager creates clients/channels")
	}
	addr, denom := os.Getenv("UNION_VOUCHER_ADDR"), os.Getenv("UNION_VOUCHER_DENOM")
	if addr == "" || denom == "" {
		t.Skip("set UNION_VOUCHER_ADDR and UNION_VOUCHER_DENOM to verify voucher balance")
	}

	bal, err := queryUnionBalance(cfg.UnionREST, addr, denom)
	if err != nil {
		t.Fatalf("query Union voucher balance: %v", err)
	}
	if bal <= 0 {
		t.Fatalf("voucher balance for %s/%s is %d", addr, denom, bal)
	}
	t.Logf("Union voucher balance: %d%s for %s", bal, denom, addr)
}

func waitForGnoEvent(t *testing.T, indexer, eventType string, attrs map[string]string) indexedTx {
	t.Helper()
	deadline := time.Now().Add(2 * time.Minute)
	var last error
	for time.Now().Before(deadline) {
		txs, err := queryGnoEvents(indexer, eventType, attrs)
		if err == nil && len(txs) > 0 {
			return txs[0]
		}
		last = err
		time.Sleep(time.Second)
	}
	t.Fatalf("Gno event %s attrs=%v not found: %v", eventType, attrs, last)
	return indexedTx{}
}

func queryGnoEvents(indexer, eventType string, attrs map[string]string) ([]indexedTx, error) {
	var ands []string
	for k, v := range attrs {
		ands = append(ands, fmt.Sprintf(`{ attrs: { key: { eq: %s } value: { eq: %s } } }`, strconv.Quote(k), strconv.Quote(v)))
	}
	andClause := ""
	if len(ands) != 0 {
		andClause = " _and: [" + strings.Join(ands, " ") + "]"
	}
	query := fmt.Sprintf(`{
		getTransactions(
			where: { success: { eq: true } response: { events: { GnoEvent: { type: { eq: %s } pkg_path: { eq: "gno.land/r/onbloc/ibc/union/core" }%s } } } }
			order: { heightAndIndex: DESC }
		) {
			hash
			block_height
			response { events { ... on GnoEvent { type pkg_path attrs { key value } } } }
		}
	}`, strconv.Quote(eventType), andClause)

	body, err := json.Marshal(map[string]string{"query": query})
	if err != nil {
		return nil, err
	}
	resp, err := http.Post(indexer, "application/json", bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	var out struct {
		Data struct {
			GetTransactions []indexedTx `json:"getTransactions"`
		} `json:"data"`
		Errors []struct {
			Message string `json:"message"`
		} `json:"errors"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return nil, err
	}
	if len(out.Errors) != 0 {
		return nil, fmt.Errorf("GraphQL: %s", out.Errors[0].Message)
	}
	return out.Data.GetTransactions, nil
}

func txAttr(tx indexedTx, eventType, key string) string {
	for _, ev := range tx.Response.Events {
		if ev.Type != eventType {
			continue
		}
		for _, attr := range ev.Attrs {
			if attr.Key == key {
				return attr.Value
			}
		}
	}
	return ""
}

func amountFromCoins(coins, denom string) int64 {
	for _, coin := range strings.Split(coins, ",") {
		amount, ok := strings.CutSuffix(strings.TrimSpace(coin), denom)
		if !ok {
			continue
		}
		n, _ := strconv.ParseInt(amount, 10, 64)
		return n
	}
	return 0
}

func requireGnoQEvalNonEmpty(t *testing.T, cfg config, label, expr string) {
	t.Helper()
	out := queryGnoQEval(t, cfg, expr)
	if strings.Contains(out, `("" string)`) {
		t.Fatalf("%s is not ready: %s", label, out)
	}
}
