package state

import (
	"encoding/base64"
	"fmt"
	"math/big"
	"regexp"
	"slices"
	"strconv"
	"strings"
)

var (
	addressPattern = regexp.MustCompile(`^0x[0-9a-fA-F]{40}$`)
	hashPattern    = regexp.MustCompile(`^0x[0-9a-fA-F]{64}$`)
	tagPattern     = regexp.MustCompile(`^[0-9a-fA-F]{64}$`)
	voucherPattern = regexp.MustCompile(`^ibc/[0-9a-fA-F]{40}$`)
)

// Validate checks topology compatibility and phase-required structure.
func (s State) Validate(expected Expected) error {
	if s.VoyagerRevision != expected.VoyagerRevision ||
		s.Chains != expected.Chains ||
		s.EVMTopology != (EVMTopology{
			ChainID:            expected.EVMChainID,
			AddressFingerprint: expected.TopologyFingerprint,
		}) ||
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

	requireConnections, requireChannels := false, false
	switch s.Phase {
	case PhaseConnectionSubmitting, "connection-prepared", PhaseConnectionSubmitted:
		requireConnections = true
	case PhaseChannelSubmitting, "channel-prepared", PhaseChannelSubmitted:
		requireConnections, requireChannels = true, true
	case PhaseComplete:
		requireConnections, requireChannels = true, true
	case PhaseFailedWork:
		return fmt.Errorf("resume state is terminal failed-work")
	case PhasePacketMintSubmitting, PhasePacketMintSubmitted,
		PhasePacketApproveSubmitting, PhasePacketApproveSubmitted,
		PhasePacketSendSubmitting, PhasePacketSendSubmitted, PhasePacketComplete:
		requireConnections, requireChannels = true, true
		if err := s.validatePacket(expected); err != nil {
			return err
		}
	default:
		return fmt.Errorf("unsupported resume phase: %s", s.Phase)
	}
	if requireConnections && !validHandshake(s.Connections) {
		return fmt.Errorf("resume state has invalid connection IDs")
	}
	if requireChannels && !validHandshake(s.Channels) {
		return fmt.Errorf("resume state has invalid channel IDs")
	}
	if (s.Phase == PhaseComplete ||
		strings.HasPrefix(string(s.Phase), "packet-")) && s.FailedWork.Final == nil {
		return fmt.Errorf("completed state has no failed-work final ID")
	}
	if s.FailedWork.Final != nil && *s.FailedWork.Final != s.FailedWork.Baseline {
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

func (s State) validatePacket(expected Expected) error {
	packet := s.Packet
	if packet == nil ||
		!strings.EqualFold(packet.Token, expected.PacketToken) ||
		packet.Recipient != expected.PacketRecipient ||
		packet.Amount != expected.PacketAmount ||
		!addressPattern.MatchString(packet.Sender) ||
		!voucherPattern.MatchString(packet.Voucher) ||
		!hashPattern.MatchString(packet.Salt) ||
		!tagPattern.MatchString(packet.Tag) ||
		packet.Phase != s.Phase {
		return fmt.Errorf("saved packet state does not match packet settings")
	}
	if s.FailedWork.Final == nil || packet.FailedWorkBaseline != *s.FailedWork.Final {
		return fmt.Errorf("saved packet state has inconsistent failed-work baseline")
	}
	requireMint := s.Phase != PhasePacketMintSubmitting
	requireApprove := s.Phase == PhasePacketApproveSubmitted ||
		s.Phase == PhasePacketSendSubmitting ||
		s.Phase == PhasePacketSendSubmitted ||
		s.Phase == PhasePacketComplete
	requireSendIntent := s.Phase == PhasePacketSendSubmitting ||
		s.Phase == PhasePacketSendSubmitted ||
		s.Phase == PhasePacketComplete
	requireSend := s.Phase == PhasePacketSendSubmitted || s.Phase == PhasePacketComplete
	if requireMint && !hashPattern.MatchString(packet.MintTx) {
		return fmt.Errorf("saved packet state has no mint transaction")
	}
	if requireApprove && !hashPattern.MatchString(packet.ApproveTx) {
		return fmt.Errorf("saved packet state has no approval transaction")
	}
	if requireSendIntent && (packet.BalancesBefore == nil || packet.EVMFromBlock == nil) {
		return fmt.Errorf("saved packet state has no pre-send balances")
	}
	if requireSend && (!hashPattern.MatchString(packet.SendTx) ||
		!hashPattern.MatchString(packet.PacketHash)) {
		return fmt.Errorf("saved packet state has no send transaction")
	}
	if s.Phase == PhasePacketComplete {
		return s.validateCompletedPacket(expected)
	}
	return nil
}

func (s State) validateCompletedPacket(expected Expected) error {
	packet := s.Packet
	if !validGnoTxHash(packet.GnoReceiveTx) ||
		packet.GnoWriteAckTx != packet.GnoReceiveTx ||
		!hashPattern.MatchString(packet.EVMAckTx) ||
		!packet.CommitmentCleared ||
		packet.BalanceDeltas == nil ||
		packet.FailedWorkFinal == nil ||
		*packet.FailedWorkFinal != packet.FailedWorkBaseline {
		return fmt.Errorf("completed packet state is incomplete")
	}
	for _, value := range []string{
		packet.BalancesBefore.Sender, packet.BalancesBefore.Escrow,
		packet.BalancesBefore.Recipient, packet.BalanceDeltas.Sender,
		packet.BalanceDeltas.Escrow, packet.BalanceDeltas.Recipient,
	} {
		if !nonnegativeDecimal(value) {
			return fmt.Errorf("completed packet state has malformed balances")
		}
	}
	switch packet.Outcome {
	case PacketOutcomeSuccess:
		if packet.BalanceDeltas.Sender != packet.Amount ||
			packet.BalanceDeltas.Escrow != packet.Amount ||
			packet.BalanceDeltas.Recipient != strconv.FormatInt(expected.PacketLedgerAmount, 10) {
			return fmt.Errorf("completed packet success deltas do not match")
		}
	case PacketOutcomeFailure:
		if *packet.BalanceDeltas != (Balances{Sender: "0", Escrow: "0", Recipient: "0"}) {
			return fmt.Errorf("completed packet failure was not fully refunded")
		}
	default:
		return fmt.Errorf("completed packet state has invalid outcome")
	}
	return nil
}

func validGnoTxHash(value string) bool {
	decoded, err := base64.StdEncoding.DecodeString(value)
	return err == nil && len(decoded) == 32
}

func nonnegativeDecimal(value string) bool {
	number, ok := new(big.Int).SetString(value, 10)
	return ok && number.Sign() >= 0 && number.String() == value
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
