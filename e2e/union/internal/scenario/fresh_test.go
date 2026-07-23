package scenario

import (
	"context"
	"encoding/hex"
	"errors"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/onbloc/gno-ibc/e2e/union/internal/process"
	"github.com/onbloc/gno-ibc/e2e/union/internal/state"
)

func TestFreshScenarioCallsSixClientsInDocumentedOrder(t *testing.T) {
	cfg := testConfig(t)
	cfg.CommandTimeout = time.Second
	cfg.ScenarioTimeout = time.Second
	cfg.PollInterval = 0
	cfg.EVMRefreshInterval = time.Hour
	cfg.VoyagerStopTimeout = time.Second
	cfg.CleanupTimeout = 2 * time.Second
	recorder := newFreshExecutor(cfg.StateFile)
	runner, err := newRunner(cfg, recorder, Options{Apply: true})
	if err != nil {
		t.Fatal(err)
	}
	if err := runner.Run(context.Background()); err != nil {
		t.Fatal(err)
	}
	want := []string{
		"dev.ibc->union-devnet-1 cometbls/ibc-gno",
		"union-devnet-1->dev.ibc gno/ibc-cosmwasm",
		"union-devnet-1->17000 trusted/evm/mpt/ibc-cosmwasm",
		"17000->union-devnet-1 cometbls/ibc-solidity",
		"dev.ibc->17000 state-lens/ics23/mpt/ibc-gno",
		"17000->dev.ibc proof-lens/ibc-solidity",
	}
	if strings.Join(recorder.creates, "\n") != strings.Join(want, "\n") {
		t.Fatalf("create order:\n%s", strings.Join(recorder.creates, "\n"))
	}
	if recorder.connectionSubmits != 1 || recorder.channelSubmits != 1 {
		t.Fatalf("submissions = connection:%d channel:%d",
			recorder.connectionSubmits, recorder.channelSubmits)
	}
	if !slices.Equal(recorder.intentPhases, []state.Phase{
		state.PhaseConnectionSubmitting, state.PhaseChannelSubmitting,
	}) {
		t.Fatalf("intent phases = %v", recorder.intentPhases)
	}
	saved, err := state.Load(cfg.StateFile)
	if err != nil {
		t.Fatal(err)
	}
	if saved.Phase != state.PhaseComplete {
		t.Fatalf("final phase = %s", saved.Phase)
	}
	for _, name := range []string{
		"gno-connection.json", "evm-connection.json",
		"gno-channel.json", "evm-channel.json", "commands.json", "summary.json",
	} {
		if _, err := os.Stat(filepath.Join(cfg.ArtifactDir, name)); err != nil {
			t.Fatalf("missing evidence %s: %v", name, err)
		}
	}
}

func TestBootstrapCheckpointFailureRunsNoVoyagerWrites(t *testing.T) {
	cfg := testConfig(t)
	cfg.CommandTimeout = time.Second
	cfg.ScenarioTimeout = time.Second
	cfg.PollInterval = 0
	cfg.VoyagerStopTimeout = time.Second
	cfg.CleanupTimeout = 2 * time.Second
	recorder := newFreshExecutor(cfg.StateFile)
	old := saveBootstrap
	startedAtCheckpoint := false
	saveBootstrap = func(string, state.State) error {
		startedAtCheckpoint = recorder.container
		return errors.New("checkpoint failed")
	}
	t.Cleanup(func() { saveBootstrap = old })
	runner, err := newRunner(cfg, recorder, Options{Apply: true})
	if err != nil {
		t.Fatal(err)
	}
	if err := runner.Run(context.Background()); err == nil {
		t.Fatal("checkpoint failure unexpectedly passed")
	}
	if recorder.writes != 0 {
		t.Fatalf("Voyager writes = %d, want zero", recorder.writes)
	}
	if !startedAtCheckpoint {
		t.Fatal("bootstrap checkpoint was attempted before Voyager started")
	}
}

func TestVoyagerStartFailureDoesNotCreateBootstrapCheckpoint(t *testing.T) {
	cfg := testConfig(t)
	cfg.CommandTimeout = time.Second
	cfg.ScenarioTimeout = time.Second
	cfg.VoyagerStopTimeout = time.Second
	cfg.CleanupTimeout = 2 * time.Second
	recorder := newFreshExecutor(cfg.StateFile)
	recorder.startErr = errors.New("start failed")
	runner, err := newRunner(cfg, recorder, Options{Apply: true})
	if err != nil {
		t.Fatal(err)
	}
	if err := runner.Run(context.Background()); err == nil {
		t.Fatal("Voyager start failure unexpectedly passed")
	}
	if _, err := os.Stat(runner.bootstrapFile()); !os.IsNotExist(err) {
		t.Fatalf("bootstrap checkpoint exists after Voyager start failure: %v", err)
	}
}

type freshClient struct {
	clientType, ibcInterface, counterparty string
}

type freshExecutor struct {
	dockerTestRuntime
	connectionOpen    bool
	channelOpen       bool
	stateFile         string
	clients           map[string]map[int64]freshClient
	creates           []string
	intentPhases      []state.Phase
	connectionSubmits int
	channelSubmits    int
	writes            int
}

func newFreshExecutor(stateFile string) *freshExecutor {
	return &freshExecutor{stateFile: stateFile, clients: make(map[string]map[int64]freshClient)}
}

func (e *freshExecutor) Run(ctx context.Context, command process.Command) (process.Result, error) {
	return e.dockerTestRuntime.run(ctx, command, e.voyager)
}

func (e *freshExecutor) voyager(args []string) (process.Result, error) {
	line := strings.Join(args, " ")
	switch {
	case line == "rpc info":
		return process.Result{Stdout: []byte(`{}`)}, nil
	case line == "queue query-failed --per-page 100":
		return process.Result{Stdout: []byte(`[]`)}, nil
	case strings.HasPrefix(line, "rpc latest-height "):
		return process.Result{Stdout: []byte(`"100"`)}, nil
	case strings.HasPrefix(line, "index "):
		e.writes++
		return process.Result{}, nil
	case strings.HasPrefix(line, "rpc client-info "):
		return e.clientInfo(args)
	case strings.HasPrefix(line, "rpc client-meta "):
		return e.clientMeta(args)
	case strings.HasPrefix(line, "rpc client-state "):
		chain, _ := trailingChainID(args[:len(args)-1])
		if chain == "dev.ibc" {
			return process.Result{Stdout: []byte(`{"state":{"l1_client_id":1,"l2_client_id":2,"l2_chain_id":"17000"}}`)}, nil
		}
		return process.Result{Stdout: []byte(`{"state":{"l1_client_id":1,"l2_client_id":1,"l2_chain_id":"dev.ibc"}}`)}, nil
	case strings.HasPrefix(line, "msg create-client "):
		e.writes++
		e.recordCreate(args)
		return process.Result{}, nil
	case strings.HasPrefix(line, "rpc ibc-state "):
		return e.ibcState(args)
	case strings.HasPrefix(line, "q e "):
		return e.submit(args)
	default:
		return process.Result{}, errors.New("unexpected Voyager command: " + line)
	}
}

func (e *freshExecutor) ibcState(args []string) (process.Result, error) {
	chain := args[len(args)-2]
	query := args[len(args)-1]
	if strings.Contains(query, `"connection"`) {
		if !e.connectionOpen {
			return process.Result{Stdout: []byte(`{"state":null}`)}, nil
		}
		return process.Result{Stdout: []byte(
			`{"state":{"state":"OPEN","client_id":2,"counterparty_client_id":2,` +
				`"counterparty_connection_id":1}}`,
		)}, nil
	}
	if !e.channelOpen {
		return process.Result{Stdout: []byte(`{"state":null}`)}, nil
	}
	if chain == "dev.ibc" {
		return process.Result{Stdout: []byte(
			`{"state":{"state":"OPEN","connection_id":1,"counterparty_channel_id":1,` +
				`"counterparty_port_id":"0x5555555555555555555555555555555555555555",` +
				`"version":"ucs03-zkgm-0"}}`,
		)}, nil
	}
	port := "0x" + hex.EncodeToString([]byte("gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"))
	return process.Result{Stdout: []byte(
		`{"state":{"state":"OPEN","connection_id":1,"counterparty_channel_id":1,` +
			`"counterparty_port_id":"` + port + `","version":"ucs03-zkgm-0"}}`,
	)}, nil
}

func (e *freshExecutor) submit(args []string) (process.Result, error) {
	saved, err := state.Load(e.stateFile)
	if err != nil {
		return process.Result{}, err
	}
	e.intentPhases = append(e.intentPhases, saved.Phase)
	e.writes++
	operation := args[len(args)-1]
	switch {
	case strings.Contains(operation, `"connection_open_init"`):
		e.connectionSubmits++
		e.connectionOpen = true
	case strings.Contains(operation, `"channel_open_init"`):
		e.channelSubmits++
		e.channelOpen = true
	default:
		return process.Result{}, errors.New("unexpected submission")
	}
	return process.Result{}, nil
}

func (e *freshExecutor) clientInfo(args []string) (process.Result, error) {
	chain, id := trailingChainID(args)
	client, ok := e.clients[chain][id]
	if !ok {
		return process.Result{Stdout: []byte(`null`)}, nil
	}
	return process.Result{Stdout: []byte(`{"client_type":"` + client.clientType +
		`","ibc_interface":"` + client.ibcInterface + `"}`)}, nil
}

func (e *freshExecutor) clientMeta(args []string) (process.Result, error) {
	chain, id := trailingChainID(args)
	client, ok := e.clients[chain][id]
	if !ok {
		return process.Result{Stdout: []byte(`null`)}, nil
	}
	return process.Result{Stdout: []byte(`{"counterparty_chain_id":"` +
		client.counterparty + `","counterparty_height":"10"}`)}, nil
}

func (e *freshExecutor) recordCreate(args []string) {
	chain := argumentAfter(args, "--on")
	counterparty := argumentAfter(args, "--tracking")
	clientType := argumentAfter(args, "--client-type")
	ibcInterface := argumentAfter(args, "--ibc-interface")
	id := int64(len(e.clients[chain]) + 1)
	if e.clients[chain] == nil {
		e.clients[chain] = make(map[int64]freshClient)
		id = 1
	}
	e.clients[chain][id] = freshClient{
		clientType: clientType, ibcInterface: ibcInterface, counterparty: counterparty,
	}
	e.creates = append(e.creates, chain+"->"+counterparty+" "+clientType+"/"+ibcInterface)
}
