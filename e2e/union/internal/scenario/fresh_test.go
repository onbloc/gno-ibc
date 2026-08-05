package scenario

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/onbloc/gno-ibc/e2e/union/internal/process"
)

func TestFreshScenarioPerformsAWrite(t *testing.T) {
	cfg := testConfig(t)
	cfg.CommandTimeout = time.Second
	cfg.ScenarioTimeout = time.Second
	cfg.VoyagerStopTimeout = time.Second
	cfg.CleanupTimeout = 2 * time.Second
	wrote := errors.New("write observed")
	executor := &freshExecutor{write: wrote}
	runner, err := newRunner(cfg, executor, Options{Apply: true})
	if err != nil {
		t.Fatal(err)
	}
	if err := runner.Run(context.Background()); !errors.Is(err, wrote) {
		t.Fatalf("run error = %v, want first write", err)
	}
	if executor.writes != 1 {
		t.Fatalf("writes = %d, want 1", executor.writes)
	}
}

type freshExecutor struct {
	dockerTestRuntime
	write  error
	writes int
}

func (e *freshExecutor) Run(ctx context.Context, command process.Command) (process.Result, error) {
	return e.dockerTestRuntime.run(ctx, command, func(args []string) (process.Result, error) {
		if len(args) > 0 && args[0] == "index" {
			e.writes++
			return process.Result{}, e.write
		}
		if len(args) > 1 && args[0] == "queue" {
			return process.Result{Stdout: []byte(`[]`)}, nil
		}
		if len(args) > 1 && args[0] == "rpc" {
			switch args[1] {
			case "info":
				return process.Result{Stdout: []byte(`{}`)}, nil
			case "client-info":
				return process.Result{Stdout: []byte(`null`)}, nil
			case "latest-height":
				return process.Result{Stdout: []byte(`"100"`)}, nil
			}
		}
		return process.Result{}, errors.New("unexpected Voyager command before first write")
	})
}
