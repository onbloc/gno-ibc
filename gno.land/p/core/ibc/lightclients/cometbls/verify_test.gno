package cometbls

import (
	"encoding/hex"
	"testing"
)

// Real Union devnet-1337 data from crypto/cometbls test suite.
// chainID "union-devnet-1337", block height 3405691582, timestamp 1732205251.998s.
const (
	devnetChainID     = "union-devnet-1337"
	devnetHeight      = int64(3405691582)
	devnetTimeSeconds = int64(1732205251)
	devnetTimeNanos   = int32(998131342)
)

var (
	devnetVH  = hexToH256("20DDFE7A0F75C65D876316091ECCD494A54A2BB324C872015F73E528D53CB9C4")
	devnetAH  = mustHexV("EE7E3E58F98AC95D63CE93B270981DF3EE54CA367F8D521ED1F444717595CD36")
	devnetZKP = mustHexV(
		"03CF56142A1E03D2445A82100FEAF70C1CD95A731ED85792AFFF5792EC0BDD21" +
			"08991BB56F9043A269F88903DE616A9AB99A3C5AB778E566744B060456C5616C" +
			"06BCE7F1930421768C2CBD79F88D08EC3A52D7C9A867064E973064385E9C945E" +
			"02951190DD7CE1662546733DD540188C96E608CA750FEF36B39E2577833634C7" +
			"0AE6F1A6D00DC6C21446AAF285EF35D944E8782B131300574F9A889C7E708A23" +
			"25E9A78013BBE869D38B19C602DAF69644C77D177E99ED76398BCEE13C61FDBF" +
			"2E178A5BA028A36033E54D1D9A0071E82E04079A5305347EBAC6D66F6EBFA48B" +
			"1DA1BF9DC5A51EFA292E1DC7B85D26F18422EB386C48CA75434039764448BB96" +
			"268DDC2CF683DDCA4BD83DF21C5631CF784375EEBE77EABC2DE77886BF1D4839" +
			"2C9C52E063B4A7131EAB9ABBA12A9F26888BC37366D41AC7D4BAC0BF6755ACB0" +
			"09BF9F36F380B6D0EEAABF066503A1B6E01DCC965D968D7694E01B1755E6BDD2" +
			"1C7A80B41682748F9B7151714BE34AA79AAD48BBB2A84525F6CDF812658C6E4F",
	)
)

func mustHexV(s string) []byte {
	b, err := hex.DecodeString(s)
	if err != nil {
		panic("mustHexV: " + err.Error())
	}
	return b
}

func hexToH256(s string) H256 {
	b := mustHexV(s)
	if len(b) != 32 {
		panic("hexToH256: not 32 bytes")
	}
	var out H256
	copy(out[:], b)
	return out
}

// devnetClientState returns a ClientState for the Union devnet test.
func devnetClientState() ClientState {
	return ClientState{
		ChainID:        devnetChainID,
		TrustingPeriod: 14 * 24 * 3600 * 1_000_000_000, // 14 days in ns
		MaxClockDrift:  10 * 1_000_000_000,             // 10 seconds in ns
	}
}

// devnetTrusted returns a ConsensusState at 1000 seconds before the devnet header.
func devnetTrusted() ConsensusState {
	return ConsensusState{
		Timestamp:          uint64(devnetTimeSeconds-1000) * 1_000_000_000,
		NextValidatorsHash: devnetVH,
	}
}

// devnetHeader returns the Header wrapping the devnet LightHeader.
func devnetHeader() Header {
	return Header{
		SignedHeader: LightHeader{
			Height:             devnetHeight,
			TimeSeconds:        devnetTimeSeconds,
			TimeNanos:          devnetTimeNanos,
			ValidatorsHash:     devnetVH[:],
			NextValidatorsHash: devnetVH,
			AppHash:            devnetAH,
		},
		TrustedHeight:      Height(devnetHeight - 1),
		ZeroKnowledgeProof: devnetZKP,
	}
}

// devnetNow returns a "current time" 1 second after the devnet header timestamp.
func devnetNow() uint64 {
	return uint64(devnetTimeSeconds+1) * 1_000_000_000
}

// devnetStates returns a states map with the trusted consensus state at the devnet trusted height.
func devnetStates() map[Height]ConsensusState {
	return map[Height]ConsensusState{
		devnetHeader().TrustedHeight: devnetTrusted(),
	}
}

// --- VerifyHeader tests ---

// TestVerifyHeaderOK verifies a real Union devnet-1337 ZK proof passes end-to-end.
func TestVerifyHeaderOK(t *testing.T) {
	if err := VerifyHeader(devnetClientState(), devnetTrusted(), devnetHeader(), devnetNow()); err != nil {
		t.Fatalf("VerifyHeader: %v", err)
	}
}

func TestVerifyHeaderFrozenClient(t *testing.T) {
	cs := devnetClientState()
	cs.FrozenHeight = FrozenHeight
	if err := VerifyHeader(cs, devnetTrusted(), devnetHeader(), devnetNow()); err == nil {
		t.Fatal("expected error for frozen client")
	}
}

func TestVerifyHeaderHeightNotAdvancing(t *testing.T) {
	h := devnetHeader()
	// Set trusted height equal to header height — must fail.
	h.TrustedHeight = Height(devnetHeight)
	states := map[Height]ConsensusState{
		h.TrustedHeight: devnetTrusted(),
	}
	if err := VerifyHeader(devnetClientState(), states[h.TrustedHeight], h, devnetNow()); err == nil {
		t.Fatal("expected error when header height does not exceed trusted height")
	}
}

func TestVerifyHeaderTimestampNotNewer(t *testing.T) {
	trusted := devnetTrusted()
	// Trusted timestamp = header timestamp → header is not strictly newer.
	trusted.Timestamp = uint64(devnetTimeSeconds)*1_000_000_000 + uint64(devnetTimeNanos)
	states := map[Height]ConsensusState{
		devnetHeader().TrustedHeight: trusted,
	}
	if err := VerifyHeader(devnetClientState(), states[devnetHeader().TrustedHeight], devnetHeader(), devnetNow()); err == nil {
		t.Fatal("expected error when header timestamp is not newer than trusted state")
	}
}

func TestVerifyHeaderExpiredTrustingPeriod(t *testing.T) {
	cs := devnetClientState()
	cs.TrustingPeriod = 1 // 1 nanosecond — always expired
	if err := VerifyHeader(cs, devnetTrusted(), devnetHeader(), devnetNow()); err == nil {
		t.Fatal("expected error for expired trusting period")
	}
}

func TestVerifyHeaderClockDrift(t *testing.T) {
	cs := devnetClientState()
	cs.MaxClockDrift = 0
	// now = 1 second BEFORE the header → header is in the future beyond drift.
	now := uint64(devnetTimeSeconds-1) * 1_000_000_000
	if err := VerifyHeader(cs, devnetTrusted(), devnetHeader(), now); err == nil {
		t.Fatal("expected error for clock drift violation")
	}
}

func TestVerifyHeaderTamperedProof(t *testing.T) {
	h := devnetHeader()
	// Flip one byte in the proof — ZKP verification must fail.
	h.ZeroKnowledgeProof[0] ^= 0xFF
	if err := VerifyHeader(devnetClientState(), devnetTrusted(), h, devnetNow()); err == nil {
		t.Fatal("expected error for tampered ZK proof")
	}
}

// --- VerifyMisbehaviour tests ---

func TestVerifyMisbehaviourFrozenClient(t *testing.T) {
	cs := devnetClientState()
	cs.FrozenHeight = FrozenHeight
	if err := VerifyMisbehaviour(cs, devnetTrusted(), devnetTrusted(), Misbehaviour{HeaderA: devnetHeader(), HeaderB: devnetHeader()}, devnetNow()); err == nil {
		t.Fatal("expected error for frozen client")
	}
}

func TestVerifyMisbehaviourDifferentHeights(t *testing.T) {
	hA := devnetHeader()
	hB := devnetHeader()
	hB.SignedHeader.Height++ // different height
	if err := VerifyMisbehaviour(devnetClientState(), devnetTrusted(), devnetTrusted(), Misbehaviour{HeaderA: hA, HeaderB: hB}, devnetNow()); err == nil {
		t.Fatal("expected error when misbehaviour headers have different heights")
	}
}

func TestVerifyMisbehaviourIdenticalHeaders(t *testing.T) {
	if err := VerifyMisbehaviour(devnetClientState(), devnetTrusted(), devnetTrusted(), Misbehaviour{HeaderA: devnetHeader(), HeaderB: devnetHeader()}, devnetNow()); err == nil {
		t.Fatal("expected error for identical headers (not misbehaviour)")
	}
}
