// Package process is the runner's only external command seam.
package process

import (
	"bytes"
	"context"
	"os"
	"os/exec"
)

// Command describes one external process invocation.
type Command struct {
	Name string
	Args []string
	Env  []string
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
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	err := cmd.Run()
	return Result{Stdout: stdout.Bytes(), Stderr: stderr.Bytes()}, err
}
