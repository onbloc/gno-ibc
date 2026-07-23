package unione2e

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"strconv"
	"testing"
	"time"
)

func TestDevnetReadiness(t *testing.T) {
	cfg := loadConfig()

	checkGnoReady(t, cfg.Gno)
	checkGnoIndexerReady(t, cfg.Gno)
	checkUnionReady(t, cfg.Union)
	checkEVMReady(t, cfg.EVM)
	checkBeaconReady(t, cfg.EVM)
}

func checkGnoReady(t *testing.T, cfg gnoConfig) {
	t.Helper()
	waitHTTP(t, cfg.RPC+"/status")
}

func checkGnoIndexerReady(t *testing.T, cfg gnoConfig) {
	t.Helper()
	waitGraphQL(t, cfg.Indexer)
}

func checkUnionReady(t *testing.T, cfg unionConfig) {
	t.Helper()
	wait(t, cfg.RPC, func() error {
		status, err := queryUnionStatus(cfg.RPC)
		if err != nil {
			return err
		}
		if status.ChainID != cfg.ChainID {
			return fmt.Errorf("union chain id = %q, want %q", status.ChainID, cfg.ChainID)
		}
		if status.Height <= 0 {
			return fmt.Errorf("union height must be positive, got %d", status.Height)
		}
		return nil
	})
}

func checkEVMReady(t *testing.T, cfg evmConfig) {
	t.Helper()
	wait(t, cfg.RPC, func() error {
		before, err := queryEVMBlockNumber(cfg.RPC)
		if err != nil {
			return err
		}
		chainID, err := queryEVMChainID(cfg.RPC)
		if err != nil {
			return err
		}
		wantChainID, err := strconv.ParseUint(cfg.ChainID, 10, 64)
		if err != nil {
			return fmt.Errorf("parse configured EVM chain id: %w", err)
		}
		if chainID != wantChainID {
			return fmt.Errorf("EVM chain id = %d, want %d", chainID, wantChainID)
		}
		time.Sleep(4 * time.Second)
		after, err := queryEVMBlockNumber(cfg.RPC)
		if err != nil {
			return err
		}
		if after <= before {
			return fmt.Errorf("EVM head did not advance: before=%d after=%d", before, after)
		}
		return nil
	})
}

func checkBeaconReady(t *testing.T, cfg evmConfig) {
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
