package unione2e

import (
	"bytes"
	"encoding/json"
	"fmt"
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
	if !cfg.RunPackets {
		t.Skip("set RUN_PACKET_TESTS=1 after starting gno-whitelist and Voyager")
	}
	if err := cfg.validatePacket(); err != nil {
		t.Fatal(err)
	}
	requirePacketSetup(t, cfg)
}

func waitForUnionReceive(t *testing.T, cfg config, packetHash string, proofHeight int64, baseline *voyagerBaseline) UnionTx {
	t.Helper()
	deadline := time.Now().Add(2 * time.Minute)
	recoveryAt := time.Now().Add(15 * time.Second)
	recovered := false
	for time.Now().Before(deadline) {
		txs, err := queryUnionTxs(cfg.Union.Container, "wasm-packet_recv", packetHash, 2)
		if err == nil && len(txs) > 0 {
			return txs[0]
		}
		failed := voyagerRowsAfter(t, cfg.Voyager, "failed", baseline.Failed)
		if onlyStaleClientFailures(failed) && !recovered {
			forceUpdateUnionGnoClient(t, cfg, proofHeight)
			baseline.Failed = voyagerMaxID(t, cfg.Voyager, "failed")
			enqueueGnoBlock(t, cfg.Voyager, cfg.Gno.ChainID, proofHeight)
			recovered = true
		} else if failed != "" && !onlyStaleClientFailures(failed) {
			t.Fatalf("Voyager failed before Union receive:\n%s", failed)
		} else if !recovered && time.Now().After(recoveryAt) {
			forceUpdateUnionGnoClient(t, cfg, proofHeight)
			enqueueGnoBlock(t, cfg.Voyager, cfg.Gno.ChainID, proofHeight)
			recovered = true
		}
		time.Sleep(time.Second)
	}
	t.Fatalf("Union packet receive not found after stale-client recovery=%t\nqueue stats:\n%s\nnew queue:\n%s\nnew failed:\n%s", recovered, voyagerQueueStats(t, cfg.Voyager), voyagerRowsAfter(t, cfg.Voyager, "queue", baseline.Queue), voyagerRowsAfter(t, cfg.Voyager, "failed", baseline.Failed))
	return UnionTx{}
}

func onlyStaleClientFailures(rows string) bool {
	if rows == "" {
		return false
	}
	for _, row := range strings.Split(rows, "\n") {
		if !strings.Contains(row, "10-gno: new val set cannot be trusted") {
			return false
		}
	}
	return true
}

func requirePacketSetup(t *testing.T, cfg config) {
	t.Helper()
	checkGnoIndexerReady(t, cfg.Gno)
	checkUnionReady(t, cfg.Union)
	requireGnoQEvalNonEmpty(t, cfg.Gno, "Gno connection "+cfg.Topology.Gno.ConnectionID, fmt.Sprintf("gno.land/r/onbloc/ibc/union/core.QueryConnection(%s)", cfg.Topology.Gno.ConnectionID))
	requireGnoQEvalNonEmpty(t, cfg.Gno, "Gno channel "+cfg.Topology.Gno.ChannelID, fmt.Sprintf("gno.land/r/onbloc/ibc/union/core.QueryChannel(%s)", cfg.Topology.Gno.ChannelID))
	requireUnionPacketSetup(t, cfg)
}

func requireUnionPacketSetup(t *testing.T, cfg config) {
	t.Helper()
	var status string
	if err := queryUnionCore(cfg.Union.Container, cfg.Union.Core, map[string]any{"get_status": map[string]any{"client_id": mustUint32(t, cfg.Topology.UnionGno.ClientID)}}, &status); err != nil || status != "active" {
		t.Fatalf("Union Gno client %s status = %q: %v", cfg.Topology.UnionGno.ClientID, status, err)
	}
	var connection struct {
		State                    string `json:"state"`
		ClientID                 uint32 `json:"client_id"`
		CounterpartyClientID     uint32 `json:"counterparty_client_id"`
		CounterpartyConnectionID uint32 `json:"counterparty_connection_id"`
	}
	if err := queryUnionCore(cfg.Union.Container, cfg.Union.Core, map[string]any{"get_connection": map[string]any{"connection_id": mustUint32(t, cfg.Topology.UnionGno.ConnectionID)}}, &connection); err != nil || connection.State != "open" || connection.ClientID != mustUint32(t, cfg.Topology.UnionGno.ClientID) || connection.CounterpartyClientID != mustUint32(t, cfg.Topology.Gno.ClientID) || connection.CounterpartyConnectionID != mustUint32(t, cfg.Topology.Gno.ConnectionID) {
		t.Fatalf("Union connection %s differs: %+v: %v", cfg.Topology.UnionGno.ConnectionID, connection, err)
	}
	var channel struct {
		State                 string `json:"state"`
		ConnectionID          uint32 `json:"connection_id"`
		CounterpartyChannelID uint32 `json:"counterparty_channel_id"`
		CounterpartyPortID    string `json:"counterparty_port_id"`
		Version               string `json:"version"`
	}
	if err := queryUnionCore(cfg.Union.Container, cfg.Union.Core, map[string]any{"get_channel": map[string]any{"channel_id": mustUint32(t, cfg.Topology.UnionGno.ChannelID)}}, &channel); err != nil || channel.State != "open" || channel.ConnectionID != mustUint32(t, cfg.Topology.UnionGno.ConnectionID) || channel.CounterpartyChannelID != mustUint32(t, cfg.Topology.Gno.ChannelID) || channel.CounterpartyPortID != fmt.Sprintf("0x%x", []byte("gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm")) || channel.Version != "ucs03-zkgm-0" {
		t.Fatalf("Union channel %s differs: %+v: %v", cfg.Topology.UnionGno.ChannelID, channel, err)
	}
}

func mustUint32(t *testing.T, value string) uint32 {
	t.Helper()
	n, err := strconv.ParseUint(value, 10, 32)
	if err != nil {
		t.Fatalf("parse id %q: %v", value, err)
	}
	return uint32(n)
}

func requireOneUnionEvent(t *testing.T, cfg unionConfig, eventType, packetHash string) {
	t.Helper()
	txs, err := queryUnionTxs(cfg.Container, eventType, packetHash, 2)
	if err != nil || len(txs) != 1 {
		t.Fatalf("Union %s count = %d, want 1: %v", eventType, len(txs), err)
	}
}

func waitForUnionEvent(t *testing.T, cfg config, eventType, packetHash string) UnionTx {
	t.Helper()
	deadline := time.Now().Add(2 * time.Minute)
	var last error
	for time.Now().Before(deadline) {
		txs, err := queryUnionTxs(cfg.Union.Container, eventType, packetHash, 3)
		if err == nil && len(txs) > 0 {
			return txs[0]
		}
		last = err
		time.Sleep(time.Second)
	}
	t.Fatalf("Union event %s packet_hash=%s not found: %v\nvoyager stats:\n%s\nvoyager failed:\n%s", eventType, packetHash, last, voyagerQueueStats(t, cfg.Voyager), voyagerQueryFailed(t, cfg.Voyager))
	return UnionTx{}
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

func latestGnoEventHeight(indexer, eventType string, attrs map[string]string) int64 {
	txs, err := queryGnoEvents(indexer, eventType, attrs)
	if err != nil || len(txs) == 0 {
		return 0
	}
	return txs[0].BlockHeight
}

func waitForNewGnoEvent(t *testing.T, cfg config, eventType string, attrs map[string]string, after int64, baseline voyagerBaseline) indexedTx {
	t.Helper()
	deadline := time.Now().Add(2 * time.Minute)
	var last error
	for time.Now().Before(deadline) {
		txs, err := queryGnoEvents(cfg.Gno.Indexer, eventType, attrs)
		if err == nil {
			for _, tx := range txs {
				if tx.BlockHeight > after {
					return tx
				}
			}
		}
		last = err
		time.Sleep(time.Second)
	}
	t.Fatalf("new Gno event %s attrs=%v not found: %v\nqueue stats:\n%s\nnew queue:\n%s\nnew failed:\n%s\nnew done:\n%s", eventType, attrs, last, voyagerQueueStats(t, cfg.Voyager), voyagerRowsAfter(t, cfg.Voyager, "queue", baseline.Queue), voyagerRowsAfter(t, cfg.Voyager, "failed", baseline.Failed), voyagerRowsAfter(t, cfg.Voyager, "done", baseline.Done))
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
	resp, err := httpClient.Post(indexer, "application/json", bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("indexer HTTP %d", resp.StatusCode)
	}
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

func requireGnoQEvalNonEmpty(t *testing.T, cfg gnoConfig, label, expr string) {
	t.Helper()
	out := queryGnoQEval(t, cfg, expr)
	if strings.Contains(out, `("" string)`) {
		t.Fatalf("%s is not ready: %s", label, out)
	}
}
