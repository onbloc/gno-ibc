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

type gnoTransferRequest struct {
	ChannelID        string
	TimeoutTimestamp string
	SaltHex          string
	Version          string
	Opcode           string
	OperandHex       string
	SendCoins        string
}

func transferOnGno(t *testing.T, cfg config, req gnoTransferRequest) string {
	t.Helper()
	if req.TimeoutTimestamp == "" {
		req.TimeoutTimestamp = fmt.Sprint(time.Now().Add(time.Hour).UnixNano())
	}
	if req.SaltHex == "" {
		req.SaltHex = "0000000000000000000000000000000000000000000000000000000000000001"
	}
	if req.Version == "" {
		req.Version = "2"
	}
	if req.Opcode == "" {
		req.Opcode = "3"
	}
	return signAndBroadcastGnoCall(t, cfg, cfg.GNOKeyName,
		"gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm", "SendRaw",
		req.SendCoins,
		req.ChannelID, req.TimeoutTimestamp, req.SaltHex, req.Version, req.Opcode, req.OperandHex,
	)
}

func dockerExec(container string, args ...string) (string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	cmdArgs := append([]string{"exec", container}, args...)
	cmd := exec.CommandContext(ctx, "docker", cmdArgs...)
	out, err := cmd.CombinedOutput()
	return string(out), err
}

func voyagerCLI(t *testing.T, cfg config, args ...string) string {
	t.Helper()
	cmdArgs := append([]string{"./voyager", "-c", cfg.VoyagerConfig}, args...)
	out, err := dockerExec(cfg.VoyagerContainer, cmdArgs...)
	if err != nil {
		t.Fatalf("voyager %s failed: %v\n%s", strings.Join(args, " "), err, out)
	}
	return out
}

func enqueueGnoBlock(t *testing.T, cfg config, height int64) {
	t.Helper()
	enqueueVoyagerFetchBlock(t, cfg, "voyager-event-source-plugin-gno/"+cfg.GNOChainID, strconv.FormatInt(height, 10))
}

func enqueueUnionBlock(t *testing.T, cfg config, height int64) {
	t.Helper()
	enqueueVoyagerFetchBlock(t, cfg, "voyager-event-source-plugin-cosmwasm/"+cfg.UnionChainID, "1-"+strconv.FormatInt(height, 10))
}

func enqueueVoyagerFetchBlock(t *testing.T, cfg config, plugin, height string) {
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

func voyagerQueueStats(t *testing.T, cfg config) string {
	t.Helper()
	return voyagerCLI(t, cfg, "queue", "stats")
}

func voyagerQueryFailed(t *testing.T, cfg config) string {
	t.Helper()
	return voyagerCLI(t, cfg, "queue", "query-failed")
}

func requireNoVoyagerFailed(t *testing.T, cfg config) {
	t.Helper()
	out := strings.TrimSpace(voyagerQueryFailed(t, cfg))
	if out != "[]" {
		if strings.Contains(out, "10-gno: new val set cannot be trusted") {
			// TODO: generate client-state bytes and submit Union force_update_client, then retry packet_recv once.
			t.Fatalf("Voyager has stale-client failures; TODO: force_update_client recovery is intentionally not implemented yet:\n%s", out)
		}
		t.Fatalf("Voyager failed queue is not empty:\n%s", out)
	}
}

func waitVoyagerReadyEmpty(t *testing.T, cfg config) {
	t.Helper()
	deadline := time.Now().Add(2 * time.Minute)
	var last string
	for time.Now().Before(deadline) {
		last = voyagerQueueStats(t, cfg)
		if queueReadyIsZero(last) {
			return
		}
		time.Sleep(time.Second)
	}
	t.Fatalf("Voyager ready queue did not drain:\n%s\nfailed:\n%s", last, voyagerQueryFailed(t, cfg))
}

func queueReadyIsZero(stats string) bool {
	s := strings.ToLower(strings.ReplaceAll(stats, " ", ""))
	return strings.Contains(s, `"ready":0`) ||
		strings.Contains(s, "ready:0") ||
		strings.Contains(s, "ready|0") ||
		strings.Contains(s, "ready0")
}

func signAndBroadcastGnoCall(t *testing.T, cfg config, keyName, pkgPath, funcName, sendCoins string, args ...string) string {
	t.Helper()
	cmdArgs := []string{
		"compose", "exec", "-T", "gno",
		"gnokey", "maketx", "call",
		"-pkgpath", pkgPath,
		"-func", funcName,
		"-gas-fee", "5000000ugnot",
		"-gas-wanted", "200000000",
		"-broadcast",
		"-chainid", cfg.GNOChainID,
		"-remote", "localhost:26657",
		"-insecure-password-stdin",
	}
	if sendCoins != "" {
		cmdArgs = append(cmdArgs, "-send", sendCoins)
	}
	for _, arg := range args {
		cmdArgs = append(cmdArgs, "-args", arg)
	}
	cmdArgs = append(cmdArgs, keyName)

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()
	cmd := exec.CommandContext(ctx, "docker", cmdArgs...)
	cmd.Dir = cfg.GNOComposeDir
	cmd.Stdin = strings.NewReader("\n")
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("gnokey maketx call failed: %v\n%s", err, out)
	}
	return string(out)
}

func queryGnoBalance(t *testing.T, cfg config, addr, denom string) int64 {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, "docker", "compose", "exec", "-T", "gno",
		"gnokey", "query", "bank/balances/"+addr,
		"-remote", "localhost:26657",
	)
	cmd.Dir = cfg.GNOComposeDir
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("query Gno balance failed: %v\n%s", err, out)
	}
	return parseCoinAmount(t, string(out), denom)
}

func queryGnoQEval(t *testing.T, cfg config, expr string) string {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, "docker", "compose", "exec", "-T", "gno",
		"gnokey", "query", "vm/qeval",
		"-remote", "localhost:26657",
		"-data", expr,
	)
	cmd.Dir = cfg.GNOComposeDir
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("query Gno qeval failed: %v\n%s", err, out)
	}
	return string(out)
}

func waitForAcknowledgement(t *testing.T, cfg config, packetHash string) indexedTx {
	t.Helper()
	return waitForGnoEvent(t, cfg.GnoIndexer, "PacketAck", map[string]string{"packet_hash": packetHash})
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
