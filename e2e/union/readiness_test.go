package unione2e

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"strconv"
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
		before, err := queryEVMBlockNumber(cfg.EVMRPC)
		if err != nil {
			return err
		}
		chainID, err := queryEVMChainID(cfg.EVMRPC)
		if err != nil {
			return err
		}
		wantChainID, err := strconv.ParseUint(cfg.EVMChainID, 10, 64)
		if err != nil {
			return fmt.Errorf("parse configured EVM chain id: %w", err)
		}
		if chainID != wantChainID {
			return fmt.Errorf("EVM chain id = %d, want %d", chainID, wantChainID)
		}
		time.Sleep(4 * time.Second)
		after, err := queryEVMBlockNumber(cfg.EVMRPC)
		if err != nil {
			return err
		}
		if after <= before {
			return fmt.Errorf("EVM head did not advance: before=%d after=%d", before, after)
		}
		return nil
	})
}

func checkBeaconReady(t *testing.T, cfg config) {
	t.Helper()
	wait(t, cfg.BeaconAPI, func() error {
		sync, err := queryBeaconSync(cfg.BeaconAPI)
		if err != nil {
			return err
		}
		if sync.IsSyncing || sync.ELOffline || sync.SyncDistance != 0 {
			return fmt.Errorf("beacon is not ready: %+v", sync)
		}
		finalized, err := queryBeaconFinalizedEpoch(cfg.BeaconAPI)
		if err != nil {
			return err
		}
		if finalized == 0 {
			return fmt.Errorf("beacon has not finalized a non-genesis epoch")
		}
		return nil
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
		resp, err := httpClient.Get(url)
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

func waitGraphQL(t *testing.T, url string) {
	t.Helper()
	wait(t, url, func() error {
		body := bytes.NewBufferString(`{"query":"{ latestBlockHeight }"}`)
		resp, err := httpClient.Post(url, "application/json", body)
		if err != nil {
			return err
		}
		defer resp.Body.Close()
		if resp.StatusCode < 200 || resp.StatusCode >= 300 {
			b, _ := io.ReadAll(io.LimitReader(resp.Body, 256))
			return fmt.Errorf("HTTP %d: %s", resp.StatusCode, b)
		}
		var out struct {
			Data struct {
				LatestBlockHeight int64 `json:"latestBlockHeight"`
			} `json:"data"`
			Errors []struct {
				Message string `json:"message"`
			} `json:"errors"`
		}
		if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
			return err
		}
		if len(out.Errors) != 0 {
			return fmt.Errorf("GraphQL: %s", out.Errors[0].Message)
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
