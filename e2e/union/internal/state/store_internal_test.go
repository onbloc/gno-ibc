package state

import (
	"errors"
	"path/filepath"
	"strings"
	"testing"
)

func TestSaveArtifactPropagatesParentDirectorySyncFailure(t *testing.T) {
	old := syncDirectory
	syncDirectory = func(string) error { return errors.New("injected sync failure") }
	t.Cleanup(func() { syncDirectory = old })

	err := SaveArtifact(filepath.Join(t.TempDir(), "evidence.json"), []byte("{}\n"))
	if err == nil || !strings.Contains(err.Error(), "sync evidence directory") {
		t.Fatalf("error = %v, want directory sync failure", err)
	}
}
