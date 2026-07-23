// Package process is the runner's only external command seam.
package process

import (
	"bytes"
	"context"
	"io"
	"os"
	"os/exec"
)

// Command describes one external process invocation.
type Command struct {
	Name string
	Args []string
	Env  []string
	// Stdout and Stderr stream output instead of retaining it in Result.
	Stdout io.Writer
	Stderr io.Writer
}

// Result contains captured process output.
type Result struct {
	Stdout []byte
	Stderr []byte
}

// Executor runs external commands.
type Executor interface {
	Run(context.Context, Command) (Result, error)
}

// OSExecutor runs commands with os/exec.
type OSExecutor struct{}

// Run executes command and captures stdout and stderr separately.
func (OSExecutor) Run(ctx context.Context, command Command) (Result, error) {
	cmd := exec.CommandContext(ctx, command.Name, command.Args...)
	cmd.Env = append(os.Environ(), command.Env...)

	var stdout, stderr bytes.Buffer
	cmd.Stdout = command.Stdout
	if cmd.Stdout == nil {
		cmd.Stdout = &stdout
	}

	cmd.Stderr = command.Stderr
	if cmd.Stderr == nil {
		cmd.Stderr = &stderr
	}

	return Result{Stdout: stdout.Bytes(), Stderr: stderr.Bytes()}, cmd.Run()
}
