package state

import (
	"fmt"
	"slices"
	"strconv"
	"strings"
)

// Validate checks that a checkpoint describes this complete topology.
func (s State) Validate(expected Expected) error {
	if s.VoyagerRevision != expected.VoyagerRevision ||
		s.Chains != expected.Chains ||
		s.EVMTopology.ChainID != expected.EVMTopology.ChainID ||
		!strings.EqualFold(s.EVMTopology.IBCHandler, expected.EVMTopology.IBCHandler) ||
		!strings.EqualFold(s.EVMTopology.Multicall, expected.EVMTopology.Multicall) ||
		!strings.EqualFold(s.EVMTopology.ZKGM, expected.EVMTopology.ZKGM) ||
		!strings.EqualFold(s.EVMTopology.CometBLSClientImpl, expected.EVMTopology.CometBLSClientImpl) ||
		!strings.EqualFold(s.EVMTopology.ProofLensClientImpl, expected.EVMTopology.ProofLensClientImpl) ||
		s.Ports.Gno != expected.GnoPort ||
		!strings.EqualFold(s.Ports.EVM, expected.EVMPort) ||
		s.Version != expected.Version {
		return fmt.Errorf("resume state does not match this topology")
	}
	if s.Clients.GnoUnion <= 0 || s.Clients.UnionGno <= 0 || s.Clients.UnionEVM <= 0 ||
		s.Clients.EVMUnion <= 0 || s.Clients.GnoEVM <= 0 || s.Clients.EVMGno <= 0 {
		return fmt.Errorf("resume state has invalid client IDs")
	}
	plain, err := parseIDs(s.Allowlists.Plain)
	if err != nil || len(plain) == 0 {
		return fmt.Errorf("malformed saved EVM plain allowlist")
	}
	proof, err := parseIDs(s.Allowlists.ProofLens)
	if err != nil || len(proof) == 0 || overlaps(plain, proof) {
		return fmt.Errorf("malformed saved EVM Proof Lens allowlist")
	}
	if !slices.Contains(plain, s.Clients.EVMUnion) {
		return fmt.Errorf("saved EVM plain allowlist omits the EVM Union client")
	}
	if !slices.Contains(proof, s.Clients.EVMGno) {
		return fmt.Errorf("saved EVM Proof Lens allowlist omits the EVM Gno client")
	}
	if err := s.validateFailedWork(); err != nil {
		return err
	}

	if !validHandshake(s.Connections) {
		return fmt.Errorf("resume state has invalid connection IDs")
	}
	if !validHandshake(s.Channels) {
		return fmt.Errorf("resume state has invalid channel IDs")
	}
	if s.FailedWork.Final == nil {
		return fmt.Errorf("completed state has no failed-work final ID")
	}
	if *s.FailedWork.Final != s.FailedWork.Baseline {
		return fmt.Errorf("resume state has inconsistent failed-work IDs")
	}
	return nil
}

func (s State) validateFailedWork() error {
	if s.FailedWork.Baseline < 0 {
		return fmt.Errorf("resume state has invalid failed-work baseline")
	}
	seen := make(map[int64]struct{}, len(s.FailedWork.Repaired))
	for _, id := range s.FailedWork.Repaired {
		if id <= s.FailedWork.Baseline {
			return fmt.Errorf("resume state has invalid repaired failed-work ID")
		}
		if _, ok := seen[id]; ok {
			return fmt.Errorf("resume state has duplicate repaired failed-work ID")
		}
		seen[id] = struct{}{}
	}
	return nil
}

// IDs returns the validated plain and Proof Lens client allowlists.
func (a Allowlists) IDs() ([]int64, []int64, error) {
	plain, err := parseIDs(a.Plain)
	if err != nil {
		return nil, nil, err
	}
	proof, err := parseIDs(a.ProofLens)
	if err != nil || overlaps(plain, proof) {
		return nil, nil, fmt.Errorf("invalid EVM client allowlists")
	}
	return plain, proof, nil
}

func parseIDs(raw string) ([]int64, error) {
	parts := strings.Split(raw, ",")
	ids := make([]int64, 0, len(parts))
	seen := make(map[int64]struct{}, len(parts))
	for _, part := range parts {
		id, err := strconv.ParseInt(part, 10, 64)
		if err != nil || id <= 0 {
			return nil, fmt.Errorf("invalid client ID")
		}
		if _, exists := seen[id]; exists {
			return nil, fmt.Errorf("duplicate client ID")
		}
		seen[id] = struct{}{}
		ids = append(ids, id)
	}
	return ids, nil
}

func overlaps(left, right []int64) bool {
	seen := make(map[int64]struct{}, len(left))
	for _, id := range left {
		seen[id] = struct{}{}
	}
	for _, id := range right {
		if _, ok := seen[id]; ok {
			return true
		}
	}
	return false
}

func validHandshake(ids *HandshakeIDs) bool {
	return ids != nil && ids.Gno > 0 && ids.EVM > 0
}
