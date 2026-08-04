package scenario

import (
	"context"
	"crypto/sha256"
	"encoding/binary"
	"encoding/hex"
	"errors"
	"fmt"
	"strconv"
	"strings"
)

type forgedProofEvidence struct {
	Name                    string `json:"name"`
	ClientID                int64  `json:"client_id"`
	SourceHeight            int64  `json:"source_height"`
	Path                    string `json:"path"`
	ExpectedValueHash       string `json:"expected_value_hash"`
	ValidProofHash          string `json:"valid_proof_hash"`
	MutatedProofHash        string `json:"mutated_proof_hash"`
	RejectedResult          any    `json:"rejected_result"`
	RejectedEventCount      int    `json:"rejected_event_count"`
	RejectedProofCommitted  bool   `json:"rejected_proof_committed"`
	ValidControlTransaction string `json:"valid_control_transaction"`
	ValidControlEventCount  int    `json:"valid_control_event_count"`
	FinalCommittedValueHash string `json:"final_committed_value_hash"`
}

func (r *Runner) runForgedProofRejection(ctx context.Context) error {
	if r.current.Connections == nil || r.current.Channels == nil {
		return fmt.Errorf("forged proof scenario requires an open channel")
	}
	// A finalized EVM height is not necessarily available in the Gno State Lens
	// client. Update it first, then prove at the consensus height actually stored.
	r.progressf("scenario forged-proof-rejection: updating Gno EVM client")
	targetHeight, err := r.voyager.LatestFinalizedHeight(ctx, r.cfg.EVMChainID)
	if err != nil {
		return err
	}
	heightText, err := r.voyager.UpdateClientTo(
		ctx, r.cfg.GnoChainID, r.current.Clients.GnoEVM, targetHeight,
	)
	if err != nil {
		return err
	}
	height, err := strconv.ParseInt(heightText, 10, 64)
	if err != nil || height <= 0 {
		return fmt.Errorf("malformed Gno EVM client height")
	}
	r.progressf("scenario forged-proof-rejection: client updated to EVM height %d", height)
	membership, err := r.evm.ChannelMembership(
		ctx,
		r.current.Channels.EVM,
		r.current.Connections.EVM,
		r.current.Channels.Gno,
		r.cfg.GnoZKGMPort,
		r.current.Version,
	)
	if err != nil {
		return err
	}
	path, err := hex.DecodeString(strings.TrimPrefix(membership.Path, "0x"))
	if err != nil || len(path) != 32 {
		return fmt.Errorf("malformed EVM membership path")
	}
	value, err := hex.DecodeString(strings.TrimPrefix(membership.Value, "0x"))
	if err != nil || len(value) != 32 {
		return fmt.Errorf("malformed EVM membership value")
	}
	r.progressf("scenario forged-proof-rejection: generating membership proof")
	proof, err := r.voyager.EncodedMembershipProof(
		ctx,
		r.cfg.EVMChainID,
		heightText,
		fmt.Sprintf(`{"channel":{"channel_id":%d}}`, r.current.Channels.EVM),
	)
	if err != nil {
		return err
	}
	mutated, err := mutateStorageProof(proof)
	if err != nil {
		return err
	}
	clientID := r.current.Clients.GnoEVM
	committed, err := r.gno.CommittedMembershipProof(ctx, clientID, height, path)
	if err != nil {
		return err
	}
	events, err := r.gno.MembershipProofEvents(ctx, clientID, height, path)
	if err != nil {
		return err
	}
	if committed != "" || len(events) != 0 {
		return fmt.Errorf("membership proof key was already committed")
	}
	r.progressf("scenario forged-proof-rejection: submitting mutated proof")
	rejected, err := r.gno.CommitMembershipProof(ctx, clientID, height, mutated, path, value)
	if evidenceErr := r.writeEvidence("forged-proof-mutated-gnokey.json", rejected); evidenceErr != nil {
		return errors.Join(err, evidenceErr)
	}
	if err != nil {
		return err
	}
	if rejected.Accepted {
		return fmt.Errorf("forged membership proof was accepted")
	}
	r.progressf("scenario forged-proof-rejection: mutated proof rejected as expected")
	committed, err = r.gno.CommittedMembershipProof(ctx, clientID, height, path)
	if err != nil {
		return err
	}
	events, err = r.gno.MembershipProofEvents(ctx, clientID, height, path)
	if err != nil {
		return err
	}
	if committed != "" || len(events) != 0 {
		return fmt.Errorf("forged membership proof changed Gno state")
	}
	r.progressf("scenario forged-proof-rejection: submitting valid control proof")
	control, err := r.gno.CommitMembershipProof(ctx, clientID, height, proof, path, value)
	if evidenceErr := r.writeEvidence("forged-proof-valid-gnokey.json", control); evidenceErr != nil {
		return errors.Join(err, evidenceErr)
	}
	if err != nil {
		return err
	}
	if !control.Accepted {
		return fmt.Errorf("valid membership proof was rejected")
	}
	event, err := r.gno.WaitMembershipProofEvent(ctx, clientID, height, path)
	if err != nil {
		return err
	}
	committed, err = r.gno.CommittedMembershipProof(ctx, clientID, height, path)
	if err != nil {
		return err
	}
	if !strings.EqualFold(committed, membership.Commitment) {
		return fmt.Errorf("valid membership proof commitment does not match")
	}
	return r.writeEvidence("forged-proof-rejection.json", forgedProofEvidence{
		Name: "forged-proof-rejection", ClientID: clientID, SourceHeight: height,
		Path: membership.Path, ExpectedValueHash: membership.Commitment,
		ValidProofHash: proofHash(proof), MutatedProofHash: proofHash(mutated),
		RejectedResult: rejected, RejectedEventCount: len(events),
		RejectedProofCommitted: false, ValidControlTransaction: event.Tx,
		ValidControlEventCount: 1, FinalCommittedValueHash: committed,
	})
}

func proofHash(proof []byte) string {
	sum := sha256.Sum256(proof)
	return "sha256:" + hex.EncodeToString(sum[:])
}

// mutateStorageProof flips one byte inside the first non-empty MPT node while
// leaving Union's bincode framing and the valid control untouched.
func mutateStorageProof(proof []byte) ([]byte, error) {
	const header = 64
	if len(proof) < header+8 {
		return nil, fmt.Errorf("malformed encoded storage proof")
	}
	mutated := append([]byte(nil), proof...)
	count := binary.LittleEndian.Uint64(mutated[header : header+8])
	offset := header + 8
	for range count {
		if offset+8 > len(mutated) {
			return nil, fmt.Errorf("malformed encoded storage proof")
		}
		size := binary.LittleEndian.Uint64(mutated[offset : offset+8])
		offset += 8
		if size > uint64(len(mutated)-offset) {
			return nil, fmt.Errorf("malformed encoded storage proof")
		}
		if size != 0 {
			mutated[offset+int(size)-1] ^= 1
			return mutated, nil
		}
		offset += int(size)
	}
	return nil, fmt.Errorf("encoded storage proof has no MPT node")
}
