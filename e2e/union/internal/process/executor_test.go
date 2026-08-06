package process_test

import (
	"context"
	"strings"
	"testing"

	"github.com/onbloc/gno-ibc/e2e/union/internal/process"
)

func TestOSExecutorRunsCommandWithEnvironmentOverride(t *testing.T) {
	result, err := (process.OSExecutor{}).Run(context.Background(), process.Command{
		Name:  "sh",
		Args:  []string{"-c", `read value; printf '%s:%s' "$UNION_E2E_PROCESS_TEST" "$value"`},
		Env:   []string{"UNION_E2E_PROCESS_TEST=recorded"},
		Stdin: strings.NewReader("input\n"),
	})
	if err != nil {
		t.Fatal(err)
	}
	if got := string(result.Stdout); got != "recorded:input" {
		t.Fatalf("stdout = %q, want recorded input", got)
	}
}
