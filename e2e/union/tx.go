package unione2e

import (
	"context"
	"fmt"
	"os/exec"
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
