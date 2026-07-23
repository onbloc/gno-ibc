package state

import (
	"errors"
	"path/filepath"
	"strings"
	"testing"
)

func TestSavePropagatesParentDirectorySyncFailure(t *testing.T) {
	old := syncDirectory
	syncDirectory = func(string) error { return errors.New("injected sync failure") }
	t.Cleanup(func() { syncDirectory = old })

	err := Save(filepath.Join(t.TempDir(), "state.json"), State{Phase: PhaseBootstrap})
	if err == nil || !strings.Contains(err.Error(), "sync state directory") {
		t.Fatalf("error = %v, want directory sync failure", err)
	}
}
