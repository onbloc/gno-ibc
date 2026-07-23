package state

import (
	"fmt"
	"regexp"
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

	requireConnections, requireChannels := false, false
	switch s.Phase {
	case phaseConnectionSubmitting, "connection-prepared", phaseConnectionSubmitted:
		requireConnections = true
	case phaseChannelSubmitting, "channel-prepared", phaseChannelSubmitted:
		requireConnections, requireChannels = true, true
	case PhaseComplete:
		requireConnections, requireChannels = true, true
	case phaseFailedWork:
		return fmt.Errorf("resume state is terminal failed-work")
	case phasePacketMintSubmitting, phasePacketMintSubmitted,
		phasePacketApproveSubmitting, phasePacketApproveSubmitted,
		phasePacketSendSubmitting, phasePacketSendSubmitted, phasePacketComplete:
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
	requireMint := s.Phase != phasePacketMintSubmitting
	requireApprove := s.Phase == phasePacketApproveSubmitted ||
		s.Phase == phasePacketSendSubmitting ||
		s.Phase == phasePacketSendSubmitted ||
		s.Phase == phasePacketComplete
	requireSendIntent := s.Phase == phasePacketSendSubmitting ||
		s.Phase == phasePacketSendSubmitted ||
		s.Phase == phasePacketComplete
	requireSend := s.Phase == phasePacketSendSubmitted || s.Phase == phasePacketComplete
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
	if s.Phase == phasePacketComplete &&
		(!hashPattern.MatchString(packet.GnoReceiveTx) ||
			!hashPattern.MatchString(packet.EVMAckTx) ||
			packet.BalanceDeltas == nil ||
			packet.FailedWorkFinal == nil) {
		return fmt.Errorf("completed packet state is incomplete")
	}
	return nil
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
