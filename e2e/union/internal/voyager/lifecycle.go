// Package voyager owns the local Voyager container and its typed read API.
package voyager

import (
	"bytes"
	"context"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/onbloc/gno-ibc/e2e/union/internal/config"
	"github.com/onbloc/gno-ibc/e2e/union/internal/process"
)

const (
	configPath     = "/run/voyager/config.jsonc"
	binaryPath     = "/output/voyager"
	ownershipLabel = "io.onbloc.gno-ibc.e2e.run"
)

var (
	ErrNotFound          = errors.New("not found")
	ErrMalformedResponse = errors.New("malformed response")
	ErrCommand           = errors.New("command failed")
	ErrTimeout           = errors.New("timeout")
)

// Runtime owns one local Voyager container.
type Runtime struct {
	cfg        config.Config
	executor   process.Executor
	progress   io.Writer
	container  string
	runtimeDir string
	runID      string
	imageID    string
	imageReady bool
}

// New creates a runtime backed by the operating-system executor.
func New(cfg config.Config, progress io.Writer) *Runtime {
	return NewWithExecutor(cfg, process.OSExecutor{}, progress)
}

// NewWithExecutor creates a runtime on the runner's sole command seam.
func NewWithExecutor(cfg config.Config, executor process.Executor, progress io.Writer) *Runtime {
	return &Runtime{cfg: cfg, executor: executor, progress: progress}
}

// ValidateSource verifies the pinned clean Voyager checkout.
func (r *Runtime) ValidateSource(ctx context.Context) error {
	result, err := r.command(ctx, process.Command{
		Name: "git",
		Args: []string{"-C", r.cfg.UnionVoyagerDir, "rev-parse", "HEAD"},
	})
	if err != nil {
		return fmt.Errorf("UNION_VOYAGER_DIR is not a readable git checkout")
	}
	if string(bytes.TrimSpace(result.Stdout)) != r.cfg.UnionVoyagerRevision {
		return fmt.Errorf("union-voyager checkout does not match UNION_VOYAGER_REVISION")
	}
	result, err = r.command(ctx, process.Command{
		Name: "git",
		Args: []string{"-C", r.cfg.UnionVoyagerDir, "status", "--porcelain"},
	})
	if err != nil {
		return fmt.Errorf("UNION_VOYAGER_DIR is not a readable git checkout")
	}
	if len(bytes.TrimSpace(result.Stdout)) != 0 {
		return fmt.Errorf("union-voyager checkout must be clean")
	}
	return nil
}

// Start builds and starts Voyager using a private rendered configuration.
func (r *Runtime) Start(ctx context.Context, rendered []byte) error {
	dir, err := os.MkdirTemp("", "union-voyager-")
	if err != nil {
		return fmt.Errorf("create Voyager runtime directory: %w", err)
	}
	r.runtimeDir = dir
	r.runID = filepath.Base(dir)
	hostConfig := filepath.Join(dir, "config.jsonc")
	if err := os.WriteFile(hostConfig, rendered, 0o600); err != nil {
		_ = os.RemoveAll(dir)
		r.runtimeDir = ""
		r.runID = ""
		return fmt.Errorf("write Voyager configuration: %w", err)
	}
	if !r.imageReady {
		if err := r.build(ctx); err != nil {
			return err
		}
		r.imageReady = true
	}
	name := "union-channel-e2e-" + r.runID
	result, err := r.command(ctx, process.Command{
		Name: "docker",
		Args: []string{"ps", "-a", "--filter", "name=^/" + name + "$", "--format", "{{.Names}}"},
	})
	if err != nil {
		return fmt.Errorf("inspect existing Voyager container: %w", err)
	}
	if len(bytes.TrimSpace(result.Stdout)) != 0 {
		return fmt.Errorf("Voyager container already exists: %s", name)
	}
	r.container = name
	result, err = r.command(ctx, process.Command{
		Name: "docker",
		Args: []string{
			"run", "--detach", "--name", name,
			"--label", ownershipLabel + "=" + r.runID,
			"--env", "RUST_LOG=" + r.cfg.VoyagerRustLog,
			"--mount", "type=bind,src=" + hostConfig + ",dst=" + configPath + ",readonly",
			r.imageID, "-c", configPath, "start",
		},
	})
	if err != nil {
		return fmt.Errorf("start Voyager container: %w", err)
	}
	if len(bytes.TrimSpace(result.Stdout)) == 0 {
		return fmt.Errorf("%w: Docker returned no Voyager container ID", ErrMalformedResponse)
	}
	return r.waitReady(ctx)
}

func (r *Runtime) build(ctx context.Context) error {
	iidFile := filepath.Join(r.runtimeDir, "image.id")
	_, err := r.executor.Run(ctx, process.Command{
		Name: "docker",
		Args: []string{
			"build", "--file", filepath.Join(r.cfg.ScriptDir, "voyager-build.Dockerfile"),
			"--build-arg", "UNION_COMMIT=" + r.cfg.UnionVoyagerRevision,
			"--iidfile", iidFile,
			"--tag", r.cfg.VoyagerImage, r.cfg.UnionVoyagerDir,
		},
		Stdout: r.progress,
		Stderr: r.progress,
	})
	if err != nil {
		return fmt.Errorf("%w: build Voyager image", classifyContext(ctx, err))
	}
	imageID, err := os.ReadFile(iidFile)
	if err != nil {
		return fmt.Errorf("read Voyager image ID: %w", err)
	}
	r.imageID = string(bytes.TrimSpace(imageID))
	digest, ok := strings.CutPrefix(r.imageID, "sha256:")
	if !ok || len(digest) != 64 {
		return fmt.Errorf("%w: malformed Voyager image ID", ErrMalformedResponse)
	}
	if _, err := hex.DecodeString(digest); err != nil {
		return fmt.Errorf("%w: malformed Voyager image ID", ErrMalformedResponse)
	}
	result, err := r.command(ctx, process.Command{
		Name: "docker",
		Args: []string{
			"image", "inspect", "--format",
			`{{index .Config.Labels "org.opencontainers.image.revision"}}`, r.imageID,
		},
	})
	if err != nil {
		return fmt.Errorf("inspect Voyager image: %w", err)
	}
	if string(bytes.TrimSpace(result.Stdout)) != r.cfg.UnionVoyagerRevision {
		return fmt.Errorf("%w: Voyager image revision does not match", ErrMalformedResponse)
	}
	result, err = r.command(ctx, process.Command{
		Name: "docker",
		Args: []string{"image", "inspect", "--format", "{{index .Config.Entrypoint 0}}", r.imageID},
	})
	if err != nil {
		return fmt.Errorf("inspect Voyager image entrypoint: %w", err)
	}
	if string(bytes.TrimSpace(result.Stdout)) != binaryPath {
		return fmt.Errorf("%w: Voyager image entrypoint does not match", ErrMalformedResponse)
	}
	return nil
}

func (r *Runtime) waitReady(ctx context.Context) error {
	waitCtx, cancel := context.WithTimeout(ctx, r.cfg.ScenarioTimeout)
	defer cancel()
	for {
		if _, err := r.call(waitCtx, "rpc", "info"); err == nil {
			return nil
		}
		result, err := r.command(waitCtx, process.Command{
			Name: "docker",
			Args: []string{"inspect", "--format", "{{.State.Running}}", r.container},
		})
		if err != nil {
			return fmt.Errorf("inspect Voyager container: %w", err)
		}
		if !strings.EqualFold(string(bytes.TrimSpace(result.Stdout)), "true") {
			return fmt.Errorf("Voyager container exited before RPC readiness")
		}
		if err := pause(waitCtx, r.cfg.PollInterval); err != nil {
			return fmt.Errorf("%w: Voyager RPC readiness", classifyContext(waitCtx, err))
		}
	}
}

// Close stops and removes Voyager. Failed cleanup retains ownership for retry.
func (r *Runtime) Close(ctx context.Context) error {
	if r.container == "" {
		return r.removeRuntimeDir()
	}
	result, err := r.command(ctx, process.Command{
		Name: "docker",
		Args: []string{"ps", "-a", "--filter", "name=^/" + r.container + "$", "--format", "{{.Names}}"},
	})
	if err != nil {
		return fmt.Errorf("inspect Voyager container before cleanup: %w", err)
	}
	if len(bytes.TrimSpace(result.Stdout)) == 0 {
		r.container = ""
		return r.removeRuntimeDir()
	}
	result, err = r.command(ctx, process.Command{
		Name: "docker",
		Args: []string{
			"inspect", "--format", `{{index .Config.Labels "` + ownershipLabel + `"}}`, r.container,
		},
	})
	if err != nil {
		return fmt.Errorf("inspect Voyager container ownership: %w", err)
	}
	if string(bytes.TrimSpace(result.Stdout)) != r.runID {
		return fmt.Errorf("refusing to remove Voyager container not owned by this run")
	}
	if _, err := r.command(ctx, process.Command{
		Name: "docker", Args: []string{"stop", "--timeout", strconv.Itoa(int(r.cfg.VoyagerStopTimeout.Seconds())), r.container},
	}); err != nil {
		return fmt.Errorf("stop Voyager container: %w", err)
	}
	if _, err := r.command(ctx, process.Command{
		Name: "docker", Args: []string{"rm", r.container},
	}); err != nil {
		return fmt.Errorf("remove Voyager container: %w", err)
	}
	r.container = ""
	return r.removeRuntimeDir()
}

func (r *Runtime) removeRuntimeDir() error {
	err := os.RemoveAll(r.runtimeDir)
	if err == nil {
		r.runtimeDir = ""
		r.runID = ""
	}
	return err
}

func (r *Runtime) call(ctx context.Context, args ...string) (process.Result, error) {
	if r.container == "" {
		return process.Result{}, fmt.Errorf("%w: Voyager is not running", ErrCommand)
	}
	dockerArgs := []string{"exec", "--env", "RUST_LOG=", r.container, binaryPath, "-c", configPath}
	return r.command(ctx, process.Command{Name: "docker", Args: append(dockerArgs, args...)})
}

func (r *Runtime) command(ctx context.Context, command process.Command) (process.Result, error) {
	commandCtx, cancel := context.WithTimeout(ctx, r.cfg.CommandTimeout)
	defer cancel()
	result, err := r.executor.Run(commandCtx, command)
	if err != nil {
		return result, classifyContext(commandCtx, err)
	}
	return result, nil
}

func classifyContext(ctx context.Context, err error) error {
	if errors.Is(ctx.Err(), context.DeadlineExceeded) || errors.Is(err, context.DeadlineExceeded) {
		return fmt.Errorf("%w: %w", ErrTimeout, context.DeadlineExceeded)
	}
	if errors.Is(ctx.Err(), context.Canceled) || errors.Is(err, context.Canceled) {
		return context.Canceled
	}
	return fmt.Errorf("%w: %w", ErrCommand, err)
}

func (r *Runtime) restart(ctx context.Context) error {
	rendered, err := os.ReadFile(filepath.Join(r.runtimeDir, "config.jsonc"))
	if err != nil {
		return fmt.Errorf("read Voyager configuration for restart: %w", err)
	}
	return r.Restart(ctx, rendered)
}

// Restart replaces the private configuration without rebuilding the image.
func (r *Runtime) Restart(ctx context.Context, rendered []byte) error {
	if err := r.Close(ctx); err != nil {
		return err
	}
	return r.Start(ctx, rendered)
}

func pause(ctx context.Context, duration time.Duration) error {
	timer := time.NewTimer(duration)
	defer timer.Stop()
	select {
	case <-ctx.Done():
		return ctx.Err()
	case <-timer.C:
		return nil
	}
}
