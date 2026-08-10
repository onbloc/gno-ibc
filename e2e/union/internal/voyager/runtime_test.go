package voyager_test

import (
	"context"
	"errors"
	"io"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/onbloc/gno-ibc/e2e/union/internal/config"
	"github.com/onbloc/gno-ibc/e2e/union/internal/process"
	"github.com/onbloc/gno-ibc/e2e/union/internal/voyager"
)

func TestRuntimeRetainsContainerAfterCleanupFailure(t *testing.T) {
	executor := &dockerExecutor{stopErr: errors.New("stop failed")}
	runtime := startRuntime(t, executor)
	if err := runtime.Close(context.Background()); err == nil {
		t.Fatal("cleanup failure unexpectedly ignored")
	}
	if err := runtime.Close(context.Background()); err != nil {
		t.Fatalf("cleanup retry failed: %v", err)
	}
	if executor.removes != 1 {
		t.Fatalf("container removals = %d, want 1", executor.removes)
	}
}

func TestRuntimeRefusesToRemoveContainerWithAnotherOwner(t *testing.T) {
	executor := &dockerExecutor{}
	runtime := startRuntime(t, executor)
	executor.owner = "another-run"
	if err := runtime.Close(context.Background()); err == nil {
		t.Fatal("foreign container unexpectedly removed")
	}
	if executor.stops != 0 || executor.removes != 0 {
		t.Fatalf("foreign container was modified: stops=%d removes=%d", executor.stops, executor.removes)
	}
}

func TestRuntimeCleansUpAfterDockerRunFailure(t *testing.T) {
	executor := &dockerExecutor{runErr: errors.New("start failed")}
	runtime := voyager.NewWithExecutor(runtimeConfig(t), executor, io.Discard)
	if err := runtime.Start(context.Background(), []byte(`{}`)); !errors.Is(err, voyager.ErrCommand) {
		t.Fatalf("start error = %v, want command failure", err)
	}
	if err := runtime.Close(context.Background()); err != nil {
		t.Fatal(err)
	}
	if executor.removes != 1 {
		t.Fatalf("container removals = %d, want 1", executor.removes)
	}
}

func TestRuntimeCapturesBoundedLogs(t *testing.T) {
	executor := &dockerExecutor{logOutput: "timeout failed"}
	runtime := startRuntime(t, executor)
	var output strings.Builder
	if err := runtime.CaptureLogs(context.Background(), &output); err != nil {
		t.Fatal(err)
	}
	if output.String() != executor.logOutput || executor.logTail != "2000" {
		t.Fatalf("logs = %q, tail = %q", output.String(), executor.logTail)
	}
}

func TestEncodedMembershipProofRejectsMalformedOutput(t *testing.T) {
	executor := &dockerExecutor{execResponse: []byte(`"not-hex"`)}
	runtime := startRuntime(t, executor)
	_, err := runtime.EncodedMembershipProof(context.Background(), "chain", "42", `{}`)
	if !errors.Is(err, voyager.ErrMalformedResponse) {
		t.Fatalf("proof error = %v, want malformed response", err)
	}
}

func TestFailedWorkDeadlockRetriesAreBounded(t *testing.T) {
	attempts := 0
	executor := &dockerExecutor{voyager: func(args []string) (process.Result, error) {
		attempts++
		return process.Result{Stderr: []byte("deadlock detected")}, errors.New("deadlock")
	}}
	runtime := startRuntime(t, executor)
	if _, err := runtime.FailedWorkID(context.Background(), 0, nil); !errors.Is(err, voyager.ErrCommand) {
		t.Fatalf("failed-work error = %v, want command failure", err)
	}
	if attempts != 5 {
		t.Fatalf("queue attempts = %d, want 5", attempts)
	}
}

func TestFailedWorkRejectsIDsAheadOfQueue(t *testing.T) {
	for _, tc := range []struct {
		name     string
		baseline int64
		repaired []int64
	}{
		{"baseline", 6, nil},
		{"repaired", 5, []int64{6}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			executor := &dockerExecutor{voyager: staticResponse(`[{"id":5}]`)}
			runtime := startRuntime(t, executor)
			if _, err := runtime.FailedWorkID(context.Background(), tc.baseline, tc.repaired); err == nil {
				t.Fatal("ID ahead of queue unexpectedly accepted")
			}
		})
	}
}

func TestActiveQueueStats(t *testing.T) {
	executor := &dockerExecutor{voyager: staticResponse(`{"total":3,"ready":1,"optimize":{}}`)}
	runtime := startRuntime(t, executor)
	stats, err := runtime.ActiveQueueStats(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if stats.Total != 3 || stats.Ready != 1 {
		t.Fatalf("stats = %+v", stats)
	}
}

func TestWaitActiveQueuePollsUntilWorkExists(t *testing.T) {
	responses := []string{`{"total":0,"ready":0,"optimize":{}}`, `{"total":3,"ready":1,"optimize":{}}`}
	executor := &dockerExecutor{voyager: func(args []string) (process.Result, error) {
		response := responses[0]
		responses = responses[1:]
		return process.Result{Stdout: []byte(response)}, nil
	}}
	runtime := startRuntime(t, executor)
	stats, err := runtime.WaitActiveQueue(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if stats.Total != 3 || stats.Ready != 1 || len(responses) != 0 {
		t.Fatalf("stats = %+v, remaining responses = %d", stats, len(responses))
	}
}

func TestWaitFinalizedHeightPollsUntilMinimum(t *testing.T) {
	responses := []string{`"223"`, `"258"`}
	executor := &dockerExecutor{voyager: func(args []string) (process.Result, error) {
		response := responses[0]
		responses = responses[1:]
		return process.Result{Stdout: []byte(response)}, nil
	}}
	runtime := startRuntime(t, executor)
	height, err := runtime.WaitFinalizedHeight(context.Background(), "chain", 256)
	if err != nil {
		t.Fatal(err)
	}
	if height != "258" || len(responses) != 0 {
		t.Fatalf("height = %s, remaining responses = %d", height, len(responses))
	}
}

func TestUpdateClientWaitsForStoredHeight(t *testing.T) {
	writes := 0
	heights := []string{"223", "258"}
	executor := &dockerExecutor{voyager: func(args []string) (process.Result, error) {
		if args[0] == "msg" {
			writes++
			return process.Result{}, nil
		}
		height := heights[0]
		heights = heights[1:]
		return process.Result{Stdout: []byte(`{"counterparty_chain_id":"chain","counterparty_height":"` + height + `"}`)}, nil
	}}
	runtime := startRuntime(t, executor)
	height, err := runtime.UpdateClientTo(context.Background(), "chain", 2, "256")
	if err != nil {
		t.Fatal(err)
	}
	if height != "258" || writes != 1 || len(heights) != 0 {
		t.Fatalf("height = %s, writes = %d, remaining responses = %d", height, writes, len(heights))
	}
}

func TestVerifyClientRejectsInactiveStatus(t *testing.T) {
	executor := &dockerExecutor{voyager: func(args []string) (process.Result, error) {
		switch args[1] {
		case "client-info":
			return process.Result{Stdout: []byte(`{"client_type":"gno","ibc_interface":"ibc-gno"}`)}, nil
		case "client-meta":
			return process.Result{Stdout: []byte(`{"counterparty_chain_id":"counterparty","counterparty_height":"10"}`)}, nil
		default:
			return process.Result{Stdout: []byte(`"frozen"`)}, nil
		}
	}}
	runtime := startRuntime(t, executor)
	err := runtime.VerifyClient(context.Background(), voyager.ClientExpectation{
		Chain: "chain", Counterparty: "counterparty", ClientType: "gno", IBCInterface: "ibc-gno", ID: 1,
	})
	if err == nil || !strings.Contains(err.Error(), "frozen") {
		t.Fatalf("verify error = %v, want frozen status", err)
	}
}

func TestCreateClientAllocationChangePerformsNoWrite(t *testing.T) {
	clientReads, writes := 0, 0
	executor := &dockerExecutor{voyager: func(args []string) (process.Result, error) {
		if args[0] == "msg" {
			writes++
		}
		clientReads++
		if clientReads == 1 {
			return process.Result{Stdout: []byte(`{"client_type":"existing","ibc_interface":"ibc-gno"}`)}, nil
		}
		return process.Result{Stdout: []byte(`null`)}, nil
	}}
	runtime := startRuntime(t, executor)
	err := runtime.CreateClient(context.Background(), voyager.ClientCreation{
		ClientExpectation: voyager.ClientExpectation{Chain: "chain", ID: 1},
	}, 0, nil, func(int64) error { return nil })
	if err == nil || !strings.Contains(err.Error(), "allocation changed") {
		t.Fatalf("create error = %v, want allocation change", err)
	}
	if writes != 0 {
		t.Fatalf("allocation change performed %d writes", writes)
	}
}

func TestCreateClientRepairsOnlyExactFailedEvent(t *testing.T) {
	failed := `[{"id":7,"item":{"@value":{"@value":{"plugin":"voyager/event/chain","message":{"@value":{"event":{"@type":"create_client","@value":{"client_id":1,"client_type":"gno"}}}}}}}},{"id":8,"item":{"@value":{"@value":{"plugin":"voyager/event/other","message":{"@value":{"event":{"@type":"create_client","@value":{"client_id":1,"client_type":"gno"}}}}}}}}]`
	clientReads := 0
	var writes, repaired []int64
	executor := &dockerExecutor{voyager: func(args []string) (process.Result, error) {
		switch {
		case args[0] == "msg":
			writes = append(writes, 1)
			return process.Result{}, nil
		case args[0] == "queue" && args[1] == "query-failed":
			return process.Result{Stdout: []byte(failed)}, nil
		case args[0] == "queue":
			writes = append(writes, 7)
			return process.Result{}, nil
		case args[1] == "client-info":
			clientReads++
			if clientReads == 1 {
				return process.Result{Stdout: []byte(`null`)}, nil
			}
			return process.Result{Stdout: []byte(`{"client_type":"gno","ibc_interface":"ibc-gno"}`)}, nil
		case args[1] == "client-meta":
			return process.Result{Stdout: []byte(`{"counterparty_chain_id":"counterparty","counterparty_height":"10"}`)}, nil
		default:
			return process.Result{Stdout: []byte(`"active"`)}, nil
		}
	}}
	runtime := startRuntime(t, executor)
	err := runtime.CreateClient(context.Background(), voyager.ClientCreation{ClientExpectation: voyager.ClientExpectation{
		Chain: "chain", Counterparty: "counterparty", ClientType: "gno", IBCInterface: "ibc-gno", ID: 1,
	}}, 3, nil, func(id int64) error {
		repaired = append(repaired, id)
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(writes) != 2 || writes[0] != 1 || writes[1] != 7 || len(repaired) != 1 || repaired[0] != 7 {
		t.Fatalf("writes = %v, repaired = %v, want create and exact event 7", writes, repaired)
	}
}

func TestConnectionEvidencePollsUntilOpen(t *testing.T) {
	responses := []string{
		`{"state":{"state":"INIT","client_id":1,"counterparty_client_id":2}}`,
		`{"state":{"state":"OPEN","client_id":1,"counterparty_client_id":2,"counterparty_connection_id":4}}`,
	}
	executor := &dockerExecutor{voyager: func(args []string) (process.Result, error) {
		response := responses[0]
		responses = responses[1:]
		return process.Result{Stdout: []byte(response)}, nil
	}}
	runtime := startRuntime(t, executor)
	_, err := runtime.ConnectionEvidence(context.Background(), voyager.ConnectionExpectation{
		Chain: "chain", ID: 3, Client: 1, CounterpartyClient: 2, CounterpartyID: 4,
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(responses) != 0 {
		t.Fatalf("connection became OPEN without polling; remaining responses = %d", len(responses))
	}
}

func startRuntime(t *testing.T, executor *dockerExecutor) *voyager.Runtime {
	t.Helper()
	runtime := voyager.NewWithExecutor(runtimeConfig(t), executor, io.Discard)
	if err := runtime.Start(context.Background(), []byte(`{}`)); err != nil {
		t.Fatal(err)
	}
	return runtime
}

type dockerExecutor struct {
	container       string
	owner           string
	runErr, stopErr error
	stops, removes  int
	execResponse    []byte
	voyager         func([]string) (process.Result, error)
	logOutput       string
	logTail         string
}

func (e *dockerExecutor) Run(_ context.Context, command process.Command) (process.Result, error) {
	if command.Name != "docker" || len(command.Args) == 0 {
		return process.Result{}, errors.New("unexpected command")
	}
	switch command.Args[0] {
	case "image":
		line := strings.Join(command.Args, " ")
		switch {
		case strings.Contains(line, "{{.Id}}"):
			return process.Result{Stdout: []byte(testImageID)}, nil
		case strings.Contains(line, "Entrypoint"):
			return process.Result{Stdout: []byte("/output/voyager")}, nil
		default:
			return process.Result{Stdout: []byte(testVoyagerRevision)}, nil
		}
	case "ps":
		return process.Result{Stdout: []byte(e.container)}, nil
	case "run":
		e.container = argumentAfter(command.Args, "--name")
		return process.Result{Stdout: []byte("container-id")}, e.runErr
	case "exec":
		args := command.Args[7:]
		if len(args) == 2 && args[0] == "rpc" && args[1] == "info" {
			return process.Result{Stdout: []byte(`{}`)}, nil
		}
		if e.voyager != nil {
			return e.voyager(args)
		}
		if e.execResponse != nil {
			return process.Result{Stdout: e.execResponse}, nil
		}
		return process.Result{Stdout: []byte(`{}`)}, nil
	case "inspect":
		if strings.Contains(strings.Join(command.Args, " "), "io.onbloc.gno-ibc.e2e.run") {
			if e.owner != "" {
				return process.Result{Stdout: []byte(e.owner)}, nil
			}
			return process.Result{Stdout: []byte(strings.TrimPrefix(e.container, "union-channel-e2e-"))}, nil
		}
		return process.Result{Stdout: []byte("true")}, nil
	case "logs":
		e.logTail = argumentAfter(command.Args, "--tail")
		_, err := io.WriteString(command.Stdout, e.logOutput)
		return process.Result{}, err
	case "stop":
		e.stops++
		if e.stopErr != nil {
			err := e.stopErr
			e.stopErr = nil
			return process.Result{}, err
		}
		return process.Result{}, nil
	case "rm":
		e.removes++
		e.container = ""
		return process.Result{}, nil
	default:
		return process.Result{}, errors.New("unexpected Docker command")
	}
}

func staticResponse(response string) func([]string) (process.Result, error) {
	return func([]string) (process.Result, error) {
		return process.Result{Stdout: []byte(response)}, nil
	}
}

const (
	testImageID         = "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
	testVoyagerRevision = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
)

func runtimeConfig(t *testing.T) config.Config {
	t.Helper()
	t.Setenv("TMPDIR", t.TempDir())
	return config.Config{
		ScriptDir: filepath.Join("testdata", "suite"), UnionVoyagerRevision: testVoyagerRevision,
		VoyagerImage: "union-voyager-e2e:" + testVoyagerRevision[:12], VoyagerRustLog: "warn",
		CommandTimeout: time.Second, ScenarioTimeout: time.Second, VoyagerStopTimeout: time.Second,
		CleanupTimeout: 2 * time.Second,
	}
}

func argumentAfter(args []string, flag string) string {
	for i := range len(args) - 1 {
		if args[i] == flag {
			return args[i+1]
		}
	}
	return ""
}
