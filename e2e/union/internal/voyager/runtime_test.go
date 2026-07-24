package voyager_test

import (
	"context"
	"errors"
	"io"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/onbloc/gno-ibc/e2e/union/internal/config"
	"github.com/onbloc/gno-ibc/e2e/union/internal/process"
	"github.com/onbloc/gno-ibc/e2e/union/internal/state"
	"github.com/onbloc/gno-ibc/e2e/union/internal/voyager"
)

func TestRuntimeLifecycleUsesPinnedImageAndDirectDockerCommands(t *testing.T) {
	cfg := runtimeConfig(t)
	recorder := &executor{t: t, steps: []step{
		{check: func(t *testing.T, ctx context.Context, command process.Command) {
			if _, hasDeadline := ctx.Deadline(); hasDeadline {
				t.Fatal("image build unexpectedly received command timeout")
			}
			if command.Stdout == nil || command.Stderr == nil {
				t.Fatal("image build progress is not streamed")
			}
		}},
		{stdout: config.VoyagerRevision},
		{stdout: "/output/voyager"},
		{},
		{stdout: "container-id"},
		{stdout: "{}"},
		{stdout: "union-channel-e2e-go"},
		{},
		{},
	}}
	runtime := voyager.NewWithExecutor(cfg, recorder, io.Discard)
	if err := runtime.Start(context.Background(), []byte("{}\n")); err != nil {
		t.Fatal(err)
	}
	if err := runtime.Close(context.Background()); err != nil {
		t.Fatal(err)
	}
	got := commandVerbs(recorder.commands)
	want := []string{"build", "image", "image", "ps", "run", "exec", "ps", "inspect", "stop", "rm"}
	if !slices.Equal(got, want) {
		t.Fatalf("Docker verbs = %v, want %v", got, want)
	}
	build := recorder.commands[0]
	iidFile := argumentAfter(build.Args, "--iidfile")
	if !slices.Equal(build.Args, []string{
		"build", "--file", filepath.Join(cfg.ScriptDir, "voyager-build.Dockerfile"),
		"--build-arg", "UNION_COMMIT=" + config.VoyagerRevision,
		"--iidfile", iidFile,
		"--tag", cfg.VoyagerImage, cfg.UnionVoyagerDir,
	}) {
		t.Fatalf("build args = %#v", build.Args)
	}
	for _, index := range []int{1, 2} {
		args := recorder.commands[index].Args
		if args[len(args)-1] != testImageID {
			t.Fatalf("image inspection used %q, want immutable image ID", args[len(args)-1])
		}
	}
	run := strings.Join(recorder.commands[4].Args, " ")
	for _, required := range []string{
		"--label io.onbloc.gno-ibc.e2e.run=union-voyager-",
		"--env RUST_LOG=warn",
		"dst=/run/voyager/config.jsonc,readonly",
		testImageID + " -c /run/voyager/config.jsonc start",
	} {
		if !strings.Contains(run, required) {
			t.Fatalf("run args %q do not contain %q", run, required)
		}
	}
	exec := strings.Join(recorder.commands[5].Args, " ")
	if !strings.Contains(exec, "/output/voyager -c /run/voyager/config.jsonc rpc info") {
		t.Fatalf("RPC args = %q", exec)
	}
	if got := recorder.commands[8].Args; !slices.Equal(got[1:3], []string{"--timeout", "1"}) {
		t.Fatalf("stop args = %#v", got)
	}
}

func TestRuntimeFailsPromptlyWhenContainerExited(t *testing.T) {
	cfg := runtimeConfig(t)
	cfg.PollInterval = time.Hour
	recorder := &executor{steps: []step{
		{}, {stdout: config.VoyagerRevision}, {stdout: "/output/voyager"}, {},
		{stdout: "container-id"},
		{err: errors.New("not ready")},
		{stdout: "false"},
	}}
	runtime := voyager.NewWithExecutor(cfg, recorder, io.Discard)
	started := time.Now()
	err := runtime.Start(context.Background(), []byte("{}"))
	if err == nil || !strings.Contains(err.Error(), "exited") {
		t.Fatalf("error = %v, want exited-container failure", err)
	}
	if time.Since(started) > time.Second {
		t.Fatal("readiness waited after Docker reported an exited container")
	}
}

func TestRuntimeRetainsContainerAfterCleanupFailure(t *testing.T) {
	cfg := runtimeConfig(t)
	recorder := &executor{steps: []step{
		{}, {stdout: config.VoyagerRevision}, {stdout: "/output/voyager"}, {},
		{stdout: "container-id"}, {stdout: "{}"},
		{stdout: "container"}, {err: errors.New("stop failed")},
		{stdout: "container"}, {}, {},
	}}
	runtime := voyager.NewWithExecutor(cfg, recorder, io.Discard)
	if err := runtime.Start(context.Background(), []byte("{}")); err != nil {
		t.Fatal(err)
	}
	if err := runtime.Close(context.Background()); err == nil {
		t.Fatal("cleanup failure unexpectedly ignored")
	}
	if err := runtime.Close(context.Background()); err != nil {
		t.Fatalf("cleanup retry failed: %v", err)
	}
}

func TestRuntimeRefusesToRemoveContainerWithAnotherOwner(t *testing.T) {
	cfg := runtimeConfig(t)
	recorder := &executor{ownership: "another-run", steps: []step{
		{}, {stdout: config.VoyagerRevision}, {stdout: "/output/voyager"}, {},
		{stdout: "container-id"}, {stdout: "{}"}, {stdout: "container"},
	}}
	runtime := voyager.NewWithExecutor(cfg, recorder, io.Discard)
	if err := runtime.Start(context.Background(), []byte("{}")); err != nil {
		t.Fatal(err)
	}
	if err := runtime.Close(context.Background()); err == nil {
		t.Fatal("container with another ownership label unexpectedly removed")
	}
	verbs := commandVerbs(recorder.commands)
	if slices.Contains(verbs, "stop") || slices.Contains(verbs, "rm") {
		t.Fatalf("foreign container received destructive command: %v", verbs)
	}
}

func TestRuntimeCleansUpContainerAfterDockerRunError(t *testing.T) {
	cfg := runtimeConfig(t)
	recorder := &executor{steps: []step{
		{}, {stdout: config.VoyagerRevision}, {stdout: "/output/voyager"}, {},
		{err: errors.New("Docker start failed")},
		{stdout: "union-channel-e2e-go"}, {}, {},
	}}
	runtime := voyager.NewWithExecutor(cfg, recorder, io.Discard)
	if err := runtime.Start(context.Background(), []byte("{}")); !errors.Is(err, voyager.ErrCommand) {
		t.Fatalf("start error = %v, want command failure", err)
	}
	if err := runtime.Close(context.Background()); err != nil {
		t.Fatalf("cleanup after run failure: %v", err)
	}
	if got, want := commandVerbs(recorder.commands), []string{"build", "image", "image", "ps", "run", "ps", "inspect", "stop", "rm"}; !slices.Equal(got, want) {
		t.Fatalf("Docker verbs = %v, want %v", got, want)
	}
	name := argumentAfter(recorder.commands[4].Args, "--name")
	if name == "" ||
		argumentAfter(recorder.commands[5].Args, "--filter") != "name=^/"+name+"$" ||
		recorder.commands[7].Args[len(recorder.commands[7].Args)-1] != name ||
		recorder.commands[8].Args[len(recorder.commands[8].Args)-1] != name {
		t.Fatalf("cleanup did not retain exact run name %q", name)
	}
}

func TestFailedWorkRetriesDeadlocksAtMostFiveTimes(t *testing.T) {
	cfg := runtimeConfig(t)
	cfg.PollInterval = 0
	steps := startedSteps()
	for range 5 {
		steps = append(steps, step{stderr: "deadlock detected", err: errors.New("deadlock")})
	}
	recorder := &executor{steps: steps}
	runtime := voyager.NewWithExecutor(cfg, recorder, io.Discard)
	if err := runtime.Start(context.Background(), []byte("{}")); err != nil {
		t.Fatal(err)
	}
	if _, err := runtime.FailedWorkID(context.Background(), 0, nil); !errors.Is(err, voyager.ErrCommand) {
		t.Fatalf("error = %v, want command classification", err)
	}
	if got := len(recorder.commands) - 6; got != 5 {
		t.Fatalf("queue attempts = %d, want 5", got)
	}
}

func TestFailedWorkRejectsSavedIDAheadOfQueue(t *testing.T) {
	cfg := runtimeConfig(t)
	recorder := &executor{steps: startedSteps(
		step{stdout: `[{"id":5}]`},
		step{stdout: `[{"id":5}]`},
	)}
	runtime := voyager.NewWithExecutor(cfg, recorder, io.Discard)
	if err := runtime.Start(context.Background(), []byte("{}")); err != nil {
		t.Fatal(err)
	}
	if _, err := runtime.FailedWorkID(context.Background(), int64(1<<63-1), nil); err == nil {
		t.Fatal("saved failed-work ID ahead of Voyager queue unexpectedly accepted")
	}
	if _, err := runtime.FailedWorkID(context.Background(), 5, []int64{6}); err == nil {
		t.Fatal("saved repaired ID ahead of Voyager queue unexpectedly accepted")
	}
}

func TestVerifyClientDistinguishesNotFoundMalformedAndCommandFailure(t *testing.T) {
	tests := []struct {
		name   string
		result step
		want   error
		cancel bool
	}{
		{"not found", step{stdout: "null"}, voyager.ErrTimeout, false},
		{"malformed", step{stdout: `{"client_type":"gno"}`}, voyager.ErrMalformedResponse, false},
		{"command", step{err: errors.New("rpc failed")}, voyager.ErrCommand, false},
		{"timeout", step{err: context.DeadlineExceeded}, voyager.ErrTimeout, false},
		{"canceled signal", step{err: errors.New("signal: killed")}, context.Canceled, true},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			cfg := runtimeConfig(t)
			if tc.name == "not found" {
				cfg.ScenarioTimeout = time.Millisecond
				cfg.PollInterval = time.Hour
			}
			recorder := &executor{steps: startedSteps(tc.result)}
			runtime := voyager.NewWithExecutor(cfg, recorder, io.Discard)
			if err := runtime.Start(context.Background(), []byte("{}")); err != nil {
				t.Fatal(err)
			}
			ctx := context.Background()
			if tc.cancel {
				var cancel context.CancelFunc
				ctx, cancel = context.WithCancel(ctx)
				cancel()
			}
			err := runtime.VerifyClient(ctx, voyager.ClientExpectation{Chain: "chain", ID: 1})
			if !errors.Is(err, tc.want) {
				t.Fatalf("error = %v, want %v", err, tc.want)
			}
		})
	}
}

func TestEVMClientVerificationRestartsVoyagerAtMostThreeTimes(t *testing.T) {
	cfg := runtimeConfig(t)
	cfg.EVMChainID = "evm"
	cfg.EVMRefreshInterval = 0
	cfg.PollInterval = time.Millisecond
	cfg.ScenarioTimeout = 20 * time.Millisecond
	steps := startedSteps()
	for range 3 {
		steps = append(steps,
			step{stdout: "null"},
			step{stdout: "container"}, step{}, step{},
			step{}, step{stdout: "id"}, step{stdout: "{}"},
		)
	}
	missing := step{stdout: "null"}
	recorder := &executor{steps: steps, fallback: &missing}
	runtime := voyager.NewWithExecutor(cfg, recorder, io.Discard)
	if err := runtime.Start(context.Background(), []byte("{}")); err != nil {
		t.Fatal(err)
	}
	err := runtime.VerifyClient(context.Background(), voyager.ClientExpectation{Chain: cfg.EVMChainID, ID: 1})
	if !errors.Is(err, voyager.ErrTimeout) {
		t.Fatalf("error = %v, want timeout after bounded refreshes", err)
	}
	verbs := strings.Join(commandVerbs(recorder.commands), " ")
	if got := strings.Count(verbs, "build"); got != 1 {
		t.Fatalf("image builds = %d, want 1", got)
	}
	if got := strings.Count(verbs, "run"); got != 4 {
		t.Fatalf("container starts = %d, want initial plus three refreshes", got)
	}
}

func TestTypedStateQueriesRejectMissingState(t *testing.T) {
	tests := []struct {
		name  string
		check func(*voyager.Runtime) error
	}{
		{"client state", func(runtime *voyager.Runtime) error {
			return runtime.VerifyLens(context.Background(), voyager.LensExpectation{Chain: "chain", ID: 1})
		}},
		{"connection state", func(runtime *voyager.Runtime) error {
			_, err := runtime.ConnectionEvidence(
				context.Background(), voyager.ConnectionExpectation{Chain: "chain", ID: 1},
			)
			return err
		}},
		{"channel state", func(runtime *voyager.Runtime) error {
			_, err := runtime.ChannelEvidence(
				context.Background(), voyager.ChannelExpectation{Chain: "chain", ID: 1},
			)
			return err
		}},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			cfg := runtimeConfig(t)
			recorder := &executor{steps: startedSteps(step{stdout: `{}`})}
			runtime := voyager.NewWithExecutor(cfg, recorder, io.Discard)
			if err := runtime.Start(context.Background(), []byte("{}")); err != nil {
				t.Fatal(err)
			}
			if err := tc.check(runtime); !errors.Is(err, voyager.ErrMalformedResponse) {
				t.Fatalf("error = %v, want malformed response", err)
			}
		})
	}
}

func TestHandshakeVerificationPollsUntilCounterpartyIDIsOpen(t *testing.T) {
	tests := []struct {
		name    string
		pending string
		open    string
		check   func(*voyager.Runtime) error
	}{
		{
			name:    "connection",
			pending: `{"state":{"state":"INIT","client_id":1,"counterparty_client_id":2}}`,
			open:    `{"state":{"state":"OPEN","client_id":1,"counterparty_client_id":2,"counterparty_connection_id":4}}`,
			check: func(runtime *voyager.Runtime) error {
				_, err := runtime.ConnectionEvidence(context.Background(), voyager.ConnectionExpectation{
					Chain: "chain", ID: 3, Client: 1, CounterpartyClient: 2, CounterpartyID: 4,
				})
				return err
			},
		},
		{
			name:    "channel",
			pending: `{"state":{"state":"INIT","connection_id":3,"counterparty_channel_id":null,"counterparty_port_id":"port","version":"version"}}`,
			open:    `{"state":{"state":"OPEN","connection_id":3,"counterparty_channel_id":5,"counterparty_port_id":"port","version":"version"}}`,
			check: func(runtime *voyager.Runtime) error {
				_, err := runtime.ChannelEvidence(context.Background(), voyager.ChannelExpectation{
					Chain: "chain", ID: 4, Connection: 3, CounterpartyID: 5,
					CounterpartyPort: "port", Version: "version",
				})
				return err
			},
		},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			cfg := runtimeConfig(t)
			recorder := &executor{steps: startedSteps(
				step{stdout: tc.pending}, step{stdout: tc.open},
			)}
			runtime := voyager.NewWithExecutor(cfg, recorder, io.Discard)
			if err := runtime.Start(context.Background(), []byte("{}")); err != nil {
				t.Fatal(err)
			}
			if err := tc.check(runtime); err != nil {
				t.Fatal(err)
			}
		})
	}
}

func TestVerifyClientRejectsMalformedMetadata(t *testing.T) {
	cfg := runtimeConfig(t)
	recorder := &executor{steps: startedSteps(
		step{stdout: `{"client_type":"gno","ibc_interface":"ibc-cosmwasm"}`},
		step{stdout: `{"counterparty_chain_id":"counterparty"}`},
	)}
	runtime := voyager.NewWithExecutor(cfg, recorder, io.Discard)
	if err := runtime.Start(context.Background(), []byte("{}")); err != nil {
		t.Fatal(err)
	}
	err := runtime.VerifyClient(context.Background(), voyager.ClientExpectation{
		Chain: "chain", Counterparty: "counterparty", ClientType: "gno", IBCInterface: "ibc-cosmwasm", ID: 1,
	})
	if !errors.Is(err, voyager.ErrMalformedResponse) {
		t.Fatalf("error = %v, want malformed response", err)
	}
}

func TestVerifyClientRejectsInactiveStatus(t *testing.T) {
	cfg := runtimeConfig(t)
	recorder := &executor{steps: startedSteps(
		step{stdout: `{"client_type":"gno","ibc_interface":"ibc-cosmwasm"}`},
		step{stdout: `{"counterparty_chain_id":"counterparty","counterparty_height":"10"}`},
		step{stdout: `"frozen"`},
	)}
	runtime := voyager.NewWithExecutor(cfg, recorder, io.Discard)
	if err := runtime.Start(context.Background(), []byte("{}")); err != nil {
		t.Fatal(err)
	}
	err := runtime.VerifyClient(context.Background(), voyager.ClientExpectation{
		Chain: "chain", Counterparty: "counterparty", ClientType: "gno",
		IBCInterface: "ibc-cosmwasm", ID: 1,
	})
	if err == nil || !strings.Contains(err.Error(), "is frozen") {
		t.Fatalf("error = %v, want frozen status", err)
	}
}

func TestCreateClientRepairsOnlyExactFailedEventAndPersistsIt(t *testing.T) {
	cfg := runtimeConfig(t)
	failed := `[{
		"id":7,
		"item":{"@value":{"@value":{
			"plugin":"voyager/event/dev.ibc",
			"message":{"@value":{"event":{"@type":"create_client","@value":{
				"client_id":1,"client_type":"state-lens/ics23/mpt"
			}}}}
		}}}
	},{
		"id":8,
		"item":{"@value":{"@value":{
			"plugin":"voyager/event/other",
			"message":{"@value":{"event":{"@type":"create_client","@value":{
				"client_id":1,"client_type":"state-lens/ics23/mpt"
			}}}}
		}}}
	}]`
	recorder := &executor{steps: startedSteps(
		step{stdout: "null"}, step{}, step{stdout: failed},
		step{stdout: "union-channel-e2e-running"}, step{}, step{}, step{},
		step{stdout: "id"}, step{stdout: "{}"}, step{},
		step{stdout: `{"client_type":"state-lens/ics23/mpt","ibc_interface":"ibc-gno"}`},
		step{stdout: `{"counterparty_chain_id":"17000","counterparty_height":"10"}`},
		step{stdout: `"active"`},
	)}
	runtime := voyager.NewWithExecutor(cfg, recorder, io.Discard)
	if err := runtime.Start(context.Background(), []byte("{}")); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(t.TempDir(), "state.json")
	saved := state.State{FailedWork: state.FailedWork{Repaired: []int64{}}}
	err := runtime.CreateClient(context.Background(), voyager.ClientCreation{
		ClientExpectation: voyager.ClientExpectation{
			Chain: "dev.ibc", Counterparty: "17000", ClientType: "state-lens/ics23/mpt",
			IBCInterface: "ibc-gno", ID: 1,
		},
	}, 3, nil, func(id int64) error {
		saved.FailedWork.Repaired = append(saved.FailedWork.Repaired, id)
		return state.Save(path, saved)
	})
	if err != nil {
		t.Fatal(err)
	}
	loaded, err := state.Load(path)
	if err != nil {
		t.Fatal(err)
	}
	if !slices.Equal(loaded.FailedWork.Repaired, []int64{7}) {
		t.Fatalf("repaired IDs = %v", loaded.FailedWork.Repaired)
	}
	requeues := 0
	for _, command := range recorder.commands {
		if strings.Contains(strings.Join(command.Args, " "), "queue query-failed-by-id 7 -e") {
			requeues++
		}
		if strings.Contains(strings.Join(command.Args, " "), "query-failed-by-id 8") {
			t.Fatal("unrelated failed event was requeued")
		}
	}
	if requeues != 1 {
		t.Fatalf("exact requeues = %d, want one", requeues)
	}
}

func TestCreateClientAllocationChangeRunsNoWrite(t *testing.T) {
	for _, tc := range []struct {
		name     string
		expected int64
		existing int
	}{
		{"reserved plain", 1, 1},
		{"reserved Proof Lens", 2, 2},
	} {
		t.Run(tc.name, func(t *testing.T) {
			cfg := runtimeConfig(t)
			steps := startedSteps()
			for range tc.existing {
				steps = append(steps, step{
					stdout: `{"client_type":"cometbls","ibc_interface":"ibc-solidity"}`,
				})
			}
			steps = append(steps, step{stdout: "null"})
			recorder := &executor{steps: steps}
			runtime := voyager.NewWithExecutor(cfg, recorder, io.Discard)
			if err := runtime.Start(context.Background(), []byte("{}")); err != nil {
				t.Fatal(err)
			}
			err := runtime.CreateClient(context.Background(), voyager.ClientCreation{
				ClientExpectation: voyager.ClientExpectation{
					Chain: cfg.EVMChainID, Counterparty: cfg.GnoChainID,
					ClientType: "proof-lens", IBCInterface: "ibc-solidity", ID: tc.expected,
				},
			}, 0, nil, func(int64) error { return nil })
			if err == nil || !strings.Contains(err.Error(), "allocation changed") {
				t.Fatalf("error = %v, want allocation change", err)
			}
			for _, command := range recorder.commands {
				if strings.Contains(strings.Join(command.Args, " "), "msg create-client") {
					t.Fatalf("allocation change issued create command: %v", command.Args)
				}
			}
		})
	}
}

type step struct {
	stdout, stderr string
	err            error
	check          func(*testing.T, context.Context, process.Command)
}

func startedSteps(extra ...step) []step {
	return append([]step{
		{}, {stdout: config.VoyagerRevision}, {stdout: "/output/voyager"},
		{}, {stdout: "id"}, {stdout: "{}"},
	}, extra...)
}

type executor struct {
	t         *testing.T
	steps     []step
	fallback  *step
	ownership string
	commands  []process.Command
}

func (e *executor) Run(ctx context.Context, command process.Command) (process.Result, error) {
	e.commands = append(e.commands, command)
	if command.Name == "docker" && len(command.Args) > 0 {
		if command.Args[0] == "build" {
			if err := os.WriteFile(argumentAfter(command.Args, "--iidfile"), []byte(testImageID+"\n"), 0o600); err != nil {
				return process.Result{}, err
			}
		}
		if command.Args[0] == "inspect" && strings.Contains(strings.Join(command.Args, " "), "io.onbloc.gno-ibc.e2e.run") {
			if e.ownership != "" {
				return process.Result{Stdout: []byte(e.ownership)}, nil
			}
			name := command.Args[len(command.Args)-1]
			return process.Result{Stdout: []byte(strings.TrimPrefix(name, "union-channel-e2e-"))}, nil
		}
	}
	if len(e.steps) == 0 {
		if e.fallback != nil {
			return process.Result{
				Stdout: []byte(e.fallback.stdout),
				Stderr: []byte(e.fallback.stderr),
			}, e.fallback.err
		}
		return process.Result{}, errors.New("unexpected command")
	}
	current := e.steps[0]
	e.steps = e.steps[1:]
	if current.check != nil {
		current.check(e.t, ctx, command)
	}
	return process.Result{Stdout: []byte(current.stdout), Stderr: []byte(current.stderr)}, current.err
}

const testImageID = "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

func runtimeConfig(t *testing.T) config.Config {
	t.Helper()
	t.Setenv("TMPDIR", t.TempDir())
	return config.Config{
		ScriptDir:            filepath.Join("testdata", "suite"),
		UnionVoyagerDir:      filepath.Join("testdata", "voyager"),
		UnionVoyagerRevision: config.VoyagerRevision,
		VoyagerImage:         "union-voyager-e2e:" + config.VoyagerRevision[:12],
		VoyagerRustLog:       "warn",
		CommandTimeout:       time.Second,
		ScenarioTimeout:      time.Second,
		PollInterval:         0,
		EVMRefreshInterval:   time.Hour,
		VoyagerStopTimeout:   time.Second,
		CleanupTimeout:       2 * time.Second,
	}
}

func commandVerbs(commands []process.Command) []string {
	verbs := make([]string, 0, len(commands))
	for _, command := range commands {
		if command.Name == "docker" && len(command.Args) > 0 {
			verbs = append(verbs, command.Args[0])
		}
	}
	return verbs
}

func argumentAfter(args []string, flag string) string {
	for i := range len(args) - 1 {
		if args[i] == flag {
			return args[i+1]
		}
	}
	return ""
}
