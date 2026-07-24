package scenario

import (
	"context"
	"errors"
	"io"
	"os"
	"slices"
	"strings"

	"github.com/onbloc/gno-ibc/e2e/union/internal/config"
	"github.com/onbloc/gno-ibc/e2e/union/internal/evm"
	"github.com/onbloc/gno-ibc/e2e/union/internal/gno"
	"github.com/onbloc/gno-ibc/e2e/union/internal/process"
	"github.com/onbloc/gno-ibc/e2e/union/internal/union"
	"github.com/onbloc/gno-ibc/e2e/union/internal/voyager"
)

const testImageID = "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

type dockerTestRuntime struct {
	container      bool
	startErr       error
	stopContextErr error
}

func newRunner(
	cfg config.Config,
	executor process.Executor,
	options Options,
) (*Runner, error) {
	return newRunnerWithClients(
		cfg,
		options,
		voyager.NewWithExecutor(cfg, executor, io.Discard),
		evm.NewWithExecutor(cfg, executor),
		gno.NewWithExecutor(cfg, executor),
		union.New(cfg),
	)
}

func (d *dockerTestRuntime) run(
	ctx context.Context,
	command process.Command,
	voyager func([]string) (process.Result, error),
) (process.Result, error) {
	if command.Name == "git" {
		if slices.Contains(command.Args, "rev-parse") {
			return process.Result{Stdout: []byte(config.VoyagerRevision)}, nil
		}
		return process.Result{}, nil
	}
	if command.Name != "docker" || len(command.Args) == 0 {
		return process.Result{}, errors.New("unexpected command")
	}
	switch command.Args[0] {
	case "build":
		if err := os.WriteFile(argumentAfter(command.Args, "--iidfile"), []byte(testImageID+"\n"), 0o600); err != nil {
			return process.Result{}, err
		}
		return process.Result{}, nil
	case "image":
		if strings.Contains(strings.Join(command.Args, " "), "Entrypoint") {
			return process.Result{Stdout: []byte("/output/voyager")}, nil
		}
		return process.Result{Stdout: []byte(config.VoyagerRevision)}, nil
	case "ps":
		if d.container {
			return process.Result{Stdout: []byte("union-channel-e2e-running")}, nil
		}
		return process.Result{}, nil
	case "run":
		d.container = true
		return process.Result{Stdout: []byte("container-id")}, d.startErr
	case "inspect":
		joined := strings.Join(command.Args, " ")
		if strings.Contains(joined, "io.onbloc.gno-ibc.e2e.run") {
			name := command.Args[len(command.Args)-1]
			return process.Result{Stdout: []byte(strings.TrimPrefix(name, "union-channel-e2e-"))}, nil
		}
		return process.Result{Stdout: []byte("true")}, nil
	case "stop":
		d.stopContextErr = ctx.Err()
		return process.Result{}, nil
	case "rm":
		d.container = false
		return process.Result{}, nil
	case "exec":
		return voyager(command.Args[7:])
	default:
		return process.Result{}, errors.New("unexpected Docker command")
	}
}
