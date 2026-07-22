package unione2e

import (
	"context"
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

func voyagerCLI(t *testing.T, cfg voyagerConfig, args ...string) string {
	t.Helper()
	cmdArgs := append([]string{"./voyager", "-c", cfg.ConfigPath}, args...)
	out, err := dockerExec(cfg.Container, cmdArgs...)
	if err != nil {
		t.Fatalf("voyager %s failed: %v\n%s", strings.Join(args, " "), err, out)
	}
	return out
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
