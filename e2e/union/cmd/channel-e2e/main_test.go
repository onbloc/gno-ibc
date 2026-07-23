package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestResolveScriptDirUsesWrapperDirectory(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "config.jsonc.template"), []byte("{}"), 0o600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("E2E_SCRIPT_DIR", dir)
	got, err := resolveScriptDir()
	if err != nil {
		t.Fatal(err)
	}
	if got != dir {
		t.Fatalf("script directory = %q, want %q", got, dir)
	}
}
