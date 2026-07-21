package unione2e

import (
	"context"
	"encoding/json"
	"fmt"
	"os/exec"
	"strconv"
	"strings"
	"testing"
	"time"
)

type voyagerBaseline struct {
	Queue  int64
	Done   int64
	Failed int64
}

func broadcastGnoPacket(t *testing.T, cfg gnoConfig, channel, operand, sendCoins, salt string) {
	t.Helper()
	cmdArgs := []string{
		"compose", "exec", "-T", "gno",
		"gnokey", "maketx", "call",
		"-pkgpath", "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm",
		"-func", "SendRaw",
		"-gas-fee", "5000000ugnot",
		"-gas-wanted", "200000000",
		"-broadcast",
		"-chainid", cfg.ChainID,
		"-remote", "localhost:26657",
		"-insecure-password-stdin",
		"-send", sendCoins,
	}
	for _, arg := range []string{channel, fmt.Sprint(time.Now().Add(time.Hour).UnixNano()), salt, "2", "3", operand} {
		cmdArgs = append(cmdArgs, "-args", arg)
	}
	cmdArgs = append(cmdArgs, cfg.KeyName)
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()
	cmd := exec.CommandContext(ctx, "docker", cmdArgs...)
	cmd.Dir = cfg.ComposeDir
	cmd.Stdin = strings.NewReader("\n")
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("gnokey packet broadcast failed: %v\n%s", err, out)
	}
}

func dockerExec(container string, args ...string) (string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	cmdArgs := append([]string{"exec", container}, args...)
	cmd := exec.CommandContext(ctx, "docker", cmdArgs...)
	out, err := cmd.CombinedOutput()
	return string(out), err
}

func retrySequenceMismatch(run func() (string, error)) (string, error) {
	var out string
	var err error
	for range 5 {
		out, err = run()
		if err == nil || !strings.Contains(out, "account sequence mismatch") {
			return out, err
		}
		time.Sleep(time.Second)
	}
	return out, err
}

func voyagerCLI(t *testing.T, cfg voyagerConfig, args ...string) string {
	t.Helper()
	cmdArgs := append([]string{"./voyager", "-c", cfg.ConfigPath}, args...)
	out, err := dockerExec(cfg.Container, cmdArgs...)
	if err != nil {
		t.Fatalf("voyager %s failed: %v\n%s", strings.Join(args, " "), err, out)
	}
	return out
}

func enqueueGnoBlock(t *testing.T, voyager voyagerConfig, chainID string, height int64) {
	t.Helper()
	enqueueVoyagerFetchBlock(t, voyager, "voyager-event-source-plugin-gno/"+chainID, strconv.FormatInt(height, 10))
}

func enqueueUnionBlock(t *testing.T, voyager voyagerConfig, chainID string, height int64) {
	t.Helper()
	enqueueVoyagerFetchBlock(t, voyager, "voyager-event-source-plugin-cosmwasm/"+chainID, "1-"+strconv.FormatInt(height, 10))
}

func enqueueEVMBlock(t *testing.T, voyager voyagerConfig, chainID string, height uint64) {
	t.Helper()
	voyagerCLI(t, voyager, "index", chainID, "--exact", strconv.FormatUint(height, 10), "--enqueue")
}

func enqueueVoyagerFetchBlock(t *testing.T, cfg voyagerConfig, plugin, height string) {
	t.Helper()
	msg := map[string]any{
		"@type": "call",
		"@value": map[string]any{
			"@type": "plugin",
			"@value": map[string]any{
				"plugin": plugin,
				"message": map[string]any{
					"@type":  "fetch_block",
					"@value": map[string]any{"height": height},
				},
			},
		},
	}
	body, err := json.Marshal(msg)
	if err != nil {
		t.Fatal(err)
	}
	voyagerCLI(t, cfg, "queue", "enqueue", string(body))
}

func forceUpdateUnionGnoClient(t *testing.T, cfg config, proofHeight int64) {
	t.Helper()
	create := voyagerCLI(t, cfg.Voyager, "msg", "create-client",
		"--on", cfg.Union.ChainID,
		"--tracking", cfg.Gno.ChainID,
		"--ibc-interface", "ibc-cosmwasm",
		"--ibc-spec-id", "ibc-union",
		"--client-type", "gno",
		"--height", strconv.FormatInt(proofHeight, 10),
	)
	clientState, consensusState, err := clientStatesFromCreate([]byte(create))
	if err != nil {
		t.Fatalf("parse Voyager create-client output: %v\n%s", err, create)
	}
	clientID, err := strconv.ParseUint(cfg.Topology.UnionGno.ClientID, 10, 32)
	if err != nil {
		t.Fatalf("parse Union Gno client id %q: %v", cfg.Topology.UnionGno.ClientID, err)
	}
	msg, err := json.Marshal(map[string]any{"force_update_client": map[string]any{
		"client_id":             clientID,
		"client_state_bytes":    clientState,
		"consensus_state_bytes": consensusState,
	}})
	if err != nil {
		t.Fatal(err)
	}
	out, err := retrySequenceMismatch(func() (string, error) {
		return dockerExec(cfg.Union.Container,
			"uniond", "tx", "wasm", "execute", cfg.Union.Core, string(msg),
			"--from", cfg.Union.SignerKey,
			"--keyring-backend", "test",
			"--home", cfg.Union.SignerHome,
			"--chain-id", cfg.Union.ChainID,
			"--node", "tcp://localhost:26657",
			"--gas", "19000000",
			"--fees", "19000000au",
			"--yes", "--broadcast-mode", "sync", "-o", "json",
		)
	})
	if err != nil {
		t.Fatalf("force-update Union Gno client %s: %v\n%s", cfg.Topology.UnionGno.ClientID, err, out)
	}
	if err := checkCosmosTxResponse([]byte(out)); err != nil {
		t.Fatalf("force-update Union Gno client %s: %v\n%s", cfg.Topology.UnionGno.ClientID, err, out)
	}
	txHash, err := cosmosTxHash([]byte(out))
	if err != nil {
		t.Fatalf("force-update Union Gno client %s: %v\n%s", cfg.Topology.UnionGno.ClientID, err, out)
	}
	waitForUnionTx(t, cfg.Union, txHash)
	t.Logf("force-updated Union Gno client %s at Gno height %d: %s", cfg.Topology.UnionGno.ClientID, proofHeight, out)
}

func broadcastUnionPacket(t *testing.T, cfg unionConfig, channel, instruction, salt string) string {
	t.Helper()
	if instruction == "" {
		t.Fatal("empty Union instruction")
	}
	msg, err := json.Marshal(map[string]any{"send": map[string]any{
		"channel_id":        mustUint32(t, channel),
		"timeout_height":    "0",
		"timeout_timestamp": strconv.FormatInt(time.Now().Add(time.Hour).UnixNano(), 10),
		"salt":              salt,
		"instruction":       instruction,
	}})
	if err != nil {
		t.Fatal(err)
	}
	return broadcastUnionContract(t, cfg, cfg.ZKGM, string(msg))
}

func broadcastUnionContract(t *testing.T, cfg unionConfig, contract, msg string) string {
	t.Helper()
	out, err := retrySequenceMismatch(func() (string, error) {
		args := []string{"uniond", "tx", "wasm", "execute", contract, msg}
		args = append(args,
			"--from", cfg.PacketSignerKey,
			"--keyring-backend", "test",
			"--home", cfg.SignerHome,
			"--chain-id", cfg.ChainID,
			"--node", "tcp://localhost:26657",
			"--gas", "19000000",
			"--fees", "19000000au",
			"--yes", "--broadcast-mode", "sync", "-o", "json")
		return dockerExec(cfg.Container, args...)
	})
	if err != nil {
		t.Fatalf("broadcast Union contract call: %v\n%s", err, out)
	}
	if err := checkCosmosTxResponse([]byte(out)); err != nil {
		t.Fatalf("broadcast Union contract call: %v\n%s", err, out)
	}
	txHash, err := cosmosTxHash([]byte(out))
	if err != nil {
		t.Fatal(err)
	}
	return waitForUnionTx(t, cfg, txHash)
}

func waitForUnionTx(t *testing.T, cfg unionConfig, txHash string) string {
	t.Helper()
	deadline := time.Now().Add(30 * time.Second)
	var out string
	for time.Now().Before(deadline) {
		var err error
		out, err = dockerExec(cfg.Container, "uniond", "query", "tx", txHash,
			"--node", "tcp://localhost:26657", "-o", "json")
		if err == nil {
			if err := checkCosmosTxResponse([]byte(out)); err != nil {
				t.Fatalf("Union tx %s: %v\n%s", txHash, err, out)
			}
			return out
		}
		time.Sleep(time.Second)
	}
	t.Fatalf("Union tx %s was not committed:\n%s", txHash, out)
	return ""
}

func checkCosmosTxResponse(body []byte) error {
	var resp struct {
		Code   *uint32 `json:"code"`
		RawLog string  `json:"raw_log"`
	}
	if err := json.Unmarshal(body, &resp); err != nil {
		return fmt.Errorf("parse transaction response: %w", err)
	}
	if resp.Code == nil {
		return fmt.Errorf("transaction response missing code")
	}
	if *resp.Code != 0 {
		return fmt.Errorf("transaction failed with code %d: %s", *resp.Code, resp.RawLog)
	}
	return nil
}

func cosmosTxHash(body []byte) (string, error) {
	var resp struct {
		TxHash string `json:"txhash"`
	}
	if err := json.Unmarshal(body, &resp); err != nil {
		return "", fmt.Errorf("parse transaction response: %w", err)
	}
	if resp.TxHash == "" {
		return "", fmt.Errorf("transaction response missing txhash")
	}
	return resp.TxHash, nil
}

func clientStatesFromCreate(body []byte) (string, string, error) {
	var value any
	if err := json.Unmarshal(body, &value); err != nil {
		value = nil
		lines := strings.Split(strings.TrimSpace(string(body)), "\n")
		for i := len(lines) - 1; i >= 0; i-- {
			if json.Unmarshal([]byte(lines[i]), &value) == nil {
				break
			}
		}
		if value == nil {
			return "", "", err
		}
	}
	clientState, ok := findString(value, "client_state_bytes")
	if !ok {
		return "", "", fmt.Errorf("client_state_bytes not found")
	}
	consensusState, ok := findString(value, "consensus_state_bytes")
	if !ok {
		return "", "", fmt.Errorf("consensus_state_bytes not found")
	}
	return clientState, consensusState, nil
}

func findString(value any, key string) (string, bool) {
	switch value := value.(type) {
	case map[string]any:
		if found, ok := value[key].(string); ok {
			return found, true
		}
		for _, child := range value {
			if found, ok := findString(child, key); ok {
				return found, true
			}
		}
	case []any:
		for _, child := range value {
			if found, ok := findString(child, key); ok {
				return found, true
			}
		}
	}
	return "", false
}

func voyagerQueueStats(t *testing.T, cfg voyagerConfig) string {
	t.Helper()
	return voyagerCLI(t, cfg, "queue", "stats")
}

func voyagerQueryFailed(t *testing.T, cfg voyagerConfig) string {
	t.Helper()
	return voyagerCLI(t, cfg, "queue", "query-failed")
}

func captureVoyagerBaseline(t *testing.T, cfg voyagerConfig) voyagerBaseline {
	t.Helper()
	return voyagerBaseline{
		Queue:  voyagerMaxID(t, cfg, "queue"),
		Done:   voyagerMaxID(t, cfg, "done"),
		Failed: voyagerMaxID(t, cfg, "failed"),
	}
}

func voyagerMaxID(t *testing.T, cfg voyagerConfig, table string) int64 {
	t.Helper()
	out, err := dockerExec(cfg.PostgresContainer, "psql", "-U", "postgres", "-d", "postgres", "-At", "-c", "select coalesce(max(id),0) from "+table)
	if err != nil {
		t.Fatalf("query Voyager %s baseline: %v\n%s", table, err, out)
	}
	n, err := strconv.ParseInt(strings.TrimSpace(out), 10, 64)
	if err != nil {
		t.Fatalf("parse Voyager %s baseline %q: %v", table, out, err)
	}
	return n
}

func voyagerRowsAfter(t *testing.T, cfg voyagerConfig, table string, id int64) string {
	t.Helper()
	item := "item::text"
	if table == "failed" {
		item += " || ' ' || replace(message, E'\\n', ' ')"
	}
	query := fmt.Sprintf("select id || ' ' || %s from %s where id > %d order by id", item, table, id)
	out, err := dockerExec(cfg.PostgresContainer, "psql", "-U", "postgres", "-d", "postgres", "-At", "-c", query)
	if err != nil {
		t.Fatalf("query new Voyager %s rows: %v\n%s", table, err, out)
	}
	return strings.TrimSpace(out)
}

func requireNoNewVoyagerFailed(t *testing.T, cfg voyagerConfig, baseline voyagerBaseline) {
	t.Helper()
	if rows := voyagerRowsAfter(t, cfg, "failed", baseline.Failed); rows != "" {
		t.Fatalf("new Voyager failed rows:\n%s", rows)
	}
}

func queryGnoBalance(t *testing.T, cfg gnoConfig, addr, denom string) int64 {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, "docker", "compose", "exec", "-T", "gno",
		"gnokey", "query", "bank/balances/"+addr,
		"-remote", "localhost:26657",
	)
	cmd.Dir = cfg.ComposeDir
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("query Gno balance failed: %v\n%s", err, out)
	}
	return parseCoinAmount(t, string(out), denom)
}

func queryGnoQEval(t *testing.T, cfg gnoConfig, expr string) string {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, "docker", "compose", "exec", "-T", "gno",
		"gnokey", "query", "vm/qeval",
		"-remote", "localhost:26657",
		"-data", expr,
	)
	cmd.Dir = cfg.ComposeDir
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("query Gno qeval failed: %v\n%s", err, out)
	}
	return string(out)
}

func parseCoinAmount(t *testing.T, out, denom string) int64 {
	t.Helper()
	_, data, ok := strings.Cut(out, "data: ")
	if !ok {
		t.Fatalf("unexpected balance output: %s", out)
	}
	for _, coin := range strings.Split(strings.Trim(strings.TrimSpace(data), "\""), ",") {
		if amount, ok := strings.CutSuffix(coin, denom); ok {
			var n int64
			if _, err := fmt.Sscan(amount, &n); err != nil {
				t.Fatalf("parse %q balance from %q: %v", denom, out, err)
			}
			return n
		}
	}
	return 0
}
