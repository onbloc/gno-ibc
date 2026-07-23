package state

import (
	"encoding/json"
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

// Load reads one private checkpoint document.
func Load(path string) (State, error) {
	info, err := os.Lstat(path)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return State{}, fmt.Errorf("missing resume state: %s", path)
		}
		return State{}, fmt.Errorf("cannot inspect resume state")
	}
	if !info.Mode().IsRegular() || info.Mode()&os.ModeSymlink != 0 || info.Mode().Perm() != 0o600 {
		return State{}, fmt.Errorf("resume state must be a regular mode 0600 file")
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return State{}, fmt.Errorf("cannot read resume state")
	}
	var saved State
	if err := json.Unmarshal(data, &saved); err != nil {
		return State{}, fmt.Errorf("malformed resume state")
	}
	if saved.FailedWork.Repaired == nil {
		saved.FailedWork.Repaired = []int64{}
	}
	return saved, nil
}

// Save atomically replaces a private checkpoint and syncs its parent directory.
func Save(path string, saved State) error {
	data, err := json.MarshalIndent(saved, "", "  ")
	if err != nil {
		return fmt.Errorf("cannot encode state")
	}
	return atomicWrite(path, append(data, '\n'))
}

// SaveBootstrap exclusively creates the coarse non-resumable bootstrap marker.
func SaveBootstrap(path string, saved State) error {
	payload := struct {
		Phase           Phase       `json:"phase"`
		VoyagerRevision string      `json:"voyager_revision"`
		Chains          Chains      `json:"chains"`
		EVMTopology     EVMTopology `json:"evm_topology"`
	}{
		Phase:           PhaseBootstrap,
		VoyagerRevision: saved.VoyagerRevision,
		Chains:          saved.Chains,
		EVMTopology:     saved.EVMTopology,
	}
	data, err := json.Marshal(payload)
	if err != nil {
		return fmt.Errorf("cannot encode bootstrap checkpoint")
	}
	file, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
	if err != nil {
		if errors.Is(err, os.ErrExist) {
			return fmt.Errorf("bootstrap checkpoint already exists; refusing to enqueue clients again")
		}
		return fmt.Errorf("cannot create bootstrap checkpoint")
	}
	if _, err := file.Write(append(data, '\n')); err != nil {
		file.Close()
		return fmt.Errorf("cannot write bootstrap checkpoint")
	}
	if err := file.Sync(); err != nil {
		file.Close()
		return fmt.Errorf("cannot sync bootstrap checkpoint")
	}
	if err := file.Close(); err != nil {
		return fmt.Errorf("cannot close bootstrap checkpoint")
	}
	if err := syncDirectory(filepath.Dir(path)); err != nil {
		return fmt.Errorf("cannot sync bootstrap checkpoint directory: %w", err)
	}
	return nil
}

// RemoveBootstrap durably removes the marker after recoverable intent is saved.
func RemoveBootstrap(path string) error {
	if err := os.Remove(path); err != nil {
		return fmt.Errorf("cannot remove bootstrap checkpoint")
	}
	if err := syncDirectory(filepath.Dir(path)); err != nil {
		return fmt.Errorf("cannot sync bootstrap checkpoint directory: %w", err)
	}
	return nil
}

// SaveArtifact atomically writes one pre-sanitized evidence document.
func SaveArtifact(path string, data []byte) error {
	return atomicWrite(path, data)
}

// EnsureFresh rejects an artifact directory that already records bootstrap work.
func EnsureFresh(stateFile, bootstrapFile string) error {
	if _, err := os.Lstat(stateFile); err == nil {
		return fmt.Errorf("state already exists; use --resume or choose a new E2E_ARTIFACT_DIR")
	} else if !errors.Is(err, os.ErrNotExist) {
		return fmt.Errorf("cannot inspect state checkpoint")
	}
	if _, err := os.Lstat(bootstrapFile); err == nil {
		return fmt.Errorf("bootstrap checkpoint already exists; refusing to enqueue clients again")
	} else if !errors.Is(err, os.ErrNotExist) {
		return fmt.Errorf("cannot inspect bootstrap checkpoint")
	}
	return nil
}

// PrepareArtifacts verifies or creates the runner-owned artifact directory.
func PrepareArtifacts(repoRoot, scriptDir, artifactDir, stateFile string) error {
	repoRoot, _ = filepath.Abs(repoRoot)
	scriptDir, _ = filepath.Abs(scriptDir)
	artifactDir, err := filepath.Abs(artifactDir)
	if err != nil ||
		filepath.Clean(stateFile) != filepath.Join(filepath.Clean(artifactDir), "state.json") ||
		artifactDir == repoRoot ||
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
	for _, path := range []string{stateFile, filepath.Join(artifactDir, "bootstrap-in-progress.json")} {
		if info, err := os.Lstat(path); err == nil && info.Mode()&os.ModeSymlink != 0 {
			return fmt.Errorf("runner checkpoint must not be a symlink")
		}
	}
	return nil
}

func atomicWrite(path string, data []byte) error {
	dir := filepath.Dir(path)
	temp, err := os.CreateTemp(dir, "."+filepath.Base(path)+".*")
	if err != nil {
		return fmt.Errorf("cannot create state checkpoint")
	}
	tempName := temp.Name()
	defer os.Remove(tempName)
	if err := temp.Chmod(0o600); err != nil {
		temp.Close()
		return fmt.Errorf("cannot secure state checkpoint")
	}
	if _, err := temp.Write(data); err != nil {
		temp.Close()
		return fmt.Errorf("cannot write state checkpoint")
	}
	if err := temp.Sync(); err != nil {
		temp.Close()
		return fmt.Errorf("cannot sync state checkpoint")
	}
	if err := temp.Close(); err != nil {
		return fmt.Errorf("cannot close state checkpoint")
	}
	if err := renameFile(tempName, path); err != nil {
		return fmt.Errorf("cannot replace state checkpoint")
	}
	if err := syncDirectory(dir); err != nil {
		return fmt.Errorf("cannot sync state directory: %w", err)
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
