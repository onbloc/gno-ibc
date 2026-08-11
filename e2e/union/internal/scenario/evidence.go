package scenario

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/onbloc/gno-ibc/e2e/union/internal/state"
)

func (r *Runner) verifyNoNewFailedWork(ctx context.Context) error {
	baseline := r.current.FailedWork.Baseline
	if r.current.FailedWork.Final != nil {
		baseline = *r.current.FailedWork.Final
	}

	latest, err := r.voyager.FailedWorkID(ctx, baseline, r.current.FailedWork.Repaired)
	if err != nil {
		return err
	}
	if latest == baseline {
		r.current.FailedWork.Final = &latest
		return nil
	}

	r.current.FailedWork.Final = &latest
	failure := fmt.Errorf("Voyager recorded new failed work after ID %d (latest %d)", baseline, latest)

	if err := r.writeChannelEvidence(); err != nil {
		return errors.Join(failure, err)
	}
	return failure
}

func (r *Runner) saveChannelEvidence() error {
	if err := r.writeChannelEvidence(); err != nil {
		return err
	}
	return state.Save(r.cfg.StateFile, r.current)
}

func (r *Runner) writeChannelEvidence() error {
	artifacts := map[string]any{
		"gno-connection.json": r.gnoConnectionEvidence,
		"evm-connection.json": r.evmConnectionEvidence,
		"gno-channel.json":    r.gnoChannelEvidence,
		"evm-channel.json":    r.evmChannelEvidence,
	}
	for name, value := range artifacts {
		if err := r.writeEvidence(name, value); err != nil {
			return err
		}
	}
	return nil
}

func (r *Runner) writeEvidence(name string, value any) error {
	data, err := json.MarshalIndent(value, "", "  ")
	if err != nil {
		return fmt.Errorf("cannot encode evidence artifact")
	}
	data = append(data, '\n')
	if r.containsSecret(data) {
		return fmt.Errorf("artifact secret scan failed")
	}
	return state.SaveArtifact(filepath.Join(r.cfg.ArtifactDir, name), data)
}

var credentialURLPattern = regexp.MustCompile(`[[:alpha:]][[:alnum:]+.-]*://[^/@[:space:]]+:[^/@[:space:]]+@`)

func (r *Runner) containsSecret(data []byte) bool {
	if credentialURLPattern.Match(data) {
		return true
	}
	text := string(data)
	for _, secret := range []string{
		r.cfg.TrustedMPTPrivateKey, r.cfg.UnionPrivateKey,
		r.cfg.EVMPrivateKey, r.cfg.RelayerEmptyPrivateKey,
		r.cfg.RelayerOfflinePrivateKey, r.cfg.RelayerRecoveryPrivateKey,
		r.cfg.GnoPrivateKey,
	} {
		if secret != "" && strings.Contains(text, secret) {
			return true
		}
	}
	return false
}
