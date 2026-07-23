package process_test

import (
	"context"
	"testing"

	"github.com/onbloc/gno-ibc/e2e/union/internal/process"
)

func TestOSExecutorRunsCommandWithEnvironmentOverride(t *testing.T) {
	result, err := (process.OSExecutor{}).Run(context.Background(), process.Command{
		Name: "sh",
		Args: []string{"-c", `printf '%s' "$UNION_E2E_PROCESS_TEST"`},
		Env:  []string{"UNION_E2E_PROCESS_TEST=recorded"},
	})
	if err != nil {
		t.Fatal(err)
	}
	if got := string(result.Stdout); got != "recorded" {
		t.Fatalf("stdout = %q, want recorded", got)
	}
}
