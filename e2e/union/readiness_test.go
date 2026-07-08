package unione2e

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"testing"
	"time"
)

func TestDevnetReadiness(t *testing.T) {
	cfg := loadConfig()

	checkGnoReady(t, cfg)
	checkGnoIndexerReady(t, cfg)
	checkUnionReady(t, cfg)
	checkEVMReady(t, cfg)
	checkBeaconReady(t, cfg)
	if cfg.PostgresAddr != "" {
		checkPostgresReady(t, cfg)
	}
}

func TestGnoReady(t *testing.T) {
	checkGnoReady(t, loadConfig())
}

func TestGnoIndexerReady(t *testing.T) {
	checkGnoIndexerReady(t, loadConfig())
}

func TestUnionReady(t *testing.T) {
	checkUnionReady(t, loadConfig())
}

func TestEVMReady(t *testing.T) {
	checkEVMReady(t, loadConfig())
}

func TestBeaconReady(t *testing.T) {
	checkBeaconReady(t, loadConfig())
}

func TestPostgresReady(t *testing.T) {
	checkPostgresReady(t, loadConfig())
}

func TestGnoUnionEVMPacketFlow(t *testing.T) {
	cfg := loadConfig()
	if !cfg.RunPacketTests {
		t.Skip("set RUN_PACKET_TESTS=1 after Voyager creates clients/channels")
	}

	t.Skip("packet flow is covered by packet_test.go")
}

func checkGnoReady(t *testing.T, cfg config) {
	t.Helper()
	waitHTTP(t, cfg.GNORPC+"/status")
}

func checkGnoIndexerReady(t *testing.T, cfg config) {
	t.Helper()
	waitGraphQL(t, cfg.GnoIndexer)
}

func checkUnionReady(t *testing.T, cfg config) {
	t.Helper()
	wait(t, cfg.UnionRPC, func() error {
		status, err := queryUnionStatus(cfg.UnionRPC)
		if err != nil {
			return err
		}
		if status.ChainID != cfg.UnionChainID {
			return fmt.Errorf("union chain id = %q, want %q", status.ChainID, cfg.UnionChainID)
		}
		if status.Height <= 0 {
			return fmt.Errorf("union height must be positive, got %d", status.Height)
		}
		return nil
	})
}

func checkEVMReady(t *testing.T, cfg config) {
	t.Helper()
	wait(t, cfg.EVMRPC, func() error {
		if _, err := queryEVMBlockNumber(cfg.EVMRPC); err != nil {
			return err
		}
		chainID, err := queryEVMChainID(cfg.EVMRPC)
		if err != nil {
			return err
		}
		if chainID == 0 {
			return fmt.Errorf("empty EVM chain id")
		}
		return nil
	})
}

func checkBeaconReady(t *testing.T, cfg config) {
	t.Helper()
	wait(t, cfg.BeaconAPI, func() error {
		_, err := queryBeaconHead(cfg.BeaconAPI)
		return err
	})
}

func checkPostgresReady(t *testing.T, cfg config) {
	t.Helper()
	if cfg.PostgresAddr == "" {
		t.Skip("set POSTGRES_ADDR=localhost:5432 to check postgres")
	}
	wait(t, cfg.PostgresAddr, func() error {
		conn, err := net.DialTimeout("tcp", cfg.PostgresAddr, 2*time.Second)
		if err != nil {
			return err
		}
		return conn.Close()
	})
}

func waitHTTP(t *testing.T, url string) {
	t.Helper()
	wait(t, url, func() error {
		resp, err := http.Get(url)
		if err != nil {
			return err
		}
		defer resp.Body.Close()
		if resp.StatusCode < 200 || resp.StatusCode >= 300 {
			body, _ := io.ReadAll(io.LimitReader(resp.Body, 256))
			return fmt.Errorf("HTTP %d: %s", resp.StatusCode, body)
		}
		return nil
	})
}

func waitJSONRPC(t *testing.T, url, method string) {
	t.Helper()
	wait(t, url, func() error {
		req := map[string]any{"jsonrpc": "2.0", "id": 1, "method": method, "params": []any{}}
		body, err := json.Marshal(req)
		if err != nil {
			return err
		}
		resp, err := http.Post(url, "application/json", bytes.NewReader(body))
		if err != nil {
			return err
		}
		defer resp.Body.Close()
		var out struct {
			Result string `json:"result"`
			Error  any    `json:"error"`
		}
		if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
			return err
		}
		if out.Error != nil || out.Result == "" {
			return fmt.Errorf("bad JSON-RPC response: result=%q error=%v", out.Result, out.Error)
		}
		return nil
	})
}

func waitGraphQL(t *testing.T, url string) {
	t.Helper()
	wait(t, url, func() error {
		body := bytes.NewBufferString(`{"query":"{ latestBlockHeight }"}`)
		resp, err := http.Post(url, "application/json", body)
		if err != nil {
			return err
		}
		defer resp.Body.Close()
		if resp.StatusCode < 200 || resp.StatusCode >= 300 {
			b, _ := io.ReadAll(io.LimitReader(resp.Body, 256))
			return fmt.Errorf("HTTP %d: %s", resp.StatusCode, b)
		}
		return nil
	})
}

func wait(t *testing.T, name string, fn func() error) {
	t.Helper()
	deadline := time.Now().Add(2 * time.Minute)
	var last error
	for time.Now().Before(deadline) {
		if err := fn(); err == nil {
			return
		} else {
			last = err
		}
		time.Sleep(time.Second)
	}
	t.Fatalf("%s not ready: %v", name, last)
}
