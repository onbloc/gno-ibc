package state

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

const artifactMarker = "union-channel-e2e-artifacts"

var (
	renameFile    = os.Rename
	syncDirectory = syncParentDirectory
)

// SaveArtifact atomically writes one pre-sanitized evidence document.
func SaveArtifact(path string, data []byte) error {
	return atomicWrite(path, data)
}

// PrepareArtifacts verifies or creates the runner-owned artifact directory.
func PrepareArtifacts(repoRoot, scriptDir, artifactDir string) error {
	repoRoot, _ = filepath.Abs(repoRoot)
	scriptDir, _ = filepath.Abs(scriptDir)
	artifactDir, err := filepath.Abs(artifactDir)
	if err != nil || artifactDir == repoRoot ||
		artifactDir == scriptDir {
		return fmt.Errorf("unsafe E2E_ARTIFACT_DIR: %s", artifactDir)
	}
	info, err := os.Lstat(artifactDir)
	switch {
	case err == nil:
		if !info.IsDir() || info.Mode()&os.ModeSymlink != 0 {
			return fmt.Errorf("existing artifact directory is not owned by this runner: %s", artifactDir)
		}
		if err := verifyMarker(artifactDir); err != nil {
			return err
		}
		if info.Mode().Perm() != 0o700 {
			if err := os.Chmod(artifactDir, 0o700); err != nil {
				return fmt.Errorf("cannot secure artifact directory")
			}
		}
	case errors.Is(err, os.ErrNotExist):
		if err := os.MkdirAll(artifactDir, 0o700); err != nil {
			return fmt.Errorf("cannot create artifact directory")
		}
		if err := os.Chmod(artifactDir, 0o700); err != nil {
			return fmt.Errorf("cannot secure artifact directory")
		}
		if err := atomicWrite(filepath.Join(artifactDir, ".union-channel-e2e-artifacts"),
			[]byte(artifactMarker+"\n")); err != nil {
			return fmt.Errorf("cannot create artifact marker: %w", err)
		}
	default:
		return fmt.Errorf("cannot inspect artifact directory")
	}
	return nil
}

func atomicWrite(path string, data []byte) error {
	dir := filepath.Dir(path)
	temp, err := os.CreateTemp(dir, "."+filepath.Base(path)+".*")
	if err != nil {
		return fmt.Errorf("cannot create evidence artifact")
	}
	tempName := temp.Name()
	defer os.Remove(tempName)
	if err := temp.Chmod(0o600); err != nil {
		temp.Close()
		return fmt.Errorf("cannot secure evidence artifact")
	}
	if _, err := temp.Write(data); err != nil {
		temp.Close()
		return fmt.Errorf("cannot write evidence artifact")
	}
	if err := temp.Sync(); err != nil {
		temp.Close()
		return fmt.Errorf("cannot sync evidence artifact")
	}
	if err := temp.Close(); err != nil {
		return fmt.Errorf("cannot close evidence artifact")
	}
	if err := renameFile(tempName, path); err != nil {
		return fmt.Errorf("cannot replace evidence artifact")
	}
	if err := syncDirectory(dir); err != nil {
		return fmt.Errorf("cannot sync evidence directory: %w", err)
	}
	return nil
}

func syncParentDirectory(path string) error {
	dir, err := os.Open(path)
	if err != nil {
		return err
	}
	return errors.Join(dir.Sync(), dir.Close())
}

func verifyMarker(dir string) error {
	path := filepath.Join(dir, ".union-channel-e2e-artifacts")
	info, err := os.Lstat(path)
	if err != nil || !info.Mode().IsRegular() || info.Mode()&os.ModeSymlink != 0 {
		return fmt.Errorf("existing artifact directory is not owned by this runner: %s", dir)
	}
	value, err := os.ReadFile(path)
	if err != nil || strings.TrimSpace(string(value)) != artifactMarker {
		return fmt.Errorf("invalid artifact marker")
	}
	return nil
}
