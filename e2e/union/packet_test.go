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

func queryGnoForceCalls(indexer string) (string, error) {
	query := `{
		getTransactions(where: { success: { eq: true } } order: { heightAndIndex: DESC }) {
			hash
			messages {
				value {
					... on MsgCall { func }
					... on MsgRun { package { files { body } } }
				}
			}
		}
	}`
	body, err := json.Marshal(map[string]string{"query": query})
	if err != nil {
		return "", err
	}
	resp, err := httpClient.Post(indexer, "application/json", bytes.NewReader(body))
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	var out struct {
		Data struct {
			GetTransactions json.RawMessage `json:"getTransactions"`
		} `json:"data"`
		Errors []struct {
			Message string `json:"message"`
		} `json:"errors"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return "", err
	}
	if len(out.Errors) != 0 {
		return "", fmt.Errorf("GraphQL: %s", out.Errors[0].Message)
	}
	return string(out.Data.GetTransactions), nil
}

func mustUint32(t *testing.T, value string) uint32 {
	t.Helper()
	n, err := strconv.ParseUint(value, 10, 32)
	if err != nil {
		t.Fatalf("parse id %q: %v", value, err)
	}
	return uint32(n)
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
