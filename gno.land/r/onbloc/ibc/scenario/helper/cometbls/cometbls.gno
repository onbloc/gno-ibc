// Package cometbls provides a reusable real-cometbls L1 harness for state-lens
// (ics23-mpt) scenario filetests.
//
// A state-lens L2 light client verifies an L2 consensus state by proving it is
// committed in an L1 client at some height: during UpdateClient/VerifyHeader it
// calls l1.VerifyMembership(L1Height, consensusPath, proof, keccak(L2Consensus)).
// Existing statelens scenarios stub that L1 with a mockL1Client whose
// VerifyMembership always succeeds. This package instead drives a REAL cometbls
// light client as the L1:
//
//   - ProveConsensus builds an inline 2-level (iavl -> tendermint) ICS23
//     membership proof committing keccak(L2ConsensusState) at the L2 client's
//     consensus path, and returns the proof bytes plus the cometbls consensus
//     root the proof commits to.
//   - RegisterAndCreate registers the real cometbls client type with core and
//     creates an L1 client whose consensus root at L1Height equals that root.
//
// Because the seeded root is exactly what the proof computes to, the real
// cometbls VerifyMembership accepts the proof — the verification path is
// genuinely exercised, only the root is scenario-controlled rather than
// anchored to a devnet chain.
package cometbls

import (
	"crypto/keccak256"

	"gno.land/p/aib/ics23"
	"gno.land/p/onbloc/ibc/union/lightclient"
	lc "gno.land/p/onbloc/ibc/union/lightclient/cometbls"
	types "gno.land/p/onbloc/ibc/union/types"
)

// moduleKey and makeStoreKey mirror the (unexported) cometbls store-key layout
// from the lightclient package. They must match byte-for-byte for the L1
// VerifyMembership merkle path to line up with the proof keys.
var moduleKey = []byte("wasm")

func makeStoreKey(addr types.H256, key []byte) []byte {
	out := make([]byte, 0, 1+32+1+len(key))
	out = append(out, 0x03)
	out = append(out, addr[:]...)
	out = append(out, 0x00)
	out = append(out, key...)

	return out
}

// ProveConsensus builds the inline 2-level ICS23 membership proof committing
// keccak(l2ConsensusState) at ConsensusStatePath(l2ClientId, l2Height), and
// returns the encoded proof plus the cometbls consensus root it commits to.
// Seed an L1 cometbls client at the matching L1 height with this root (see
// RegisterAndCreate, using the same contractAddr) and its VerifyMembership will
// accept the proof.
//
// contractAddr is the L1 wasm contract address baked into the store keys; zero
// is fine for scenarios as long as RegisterAndCreate is given the same value.
// l2ClientId is the state-lens client's L2ClientID (the L2 client id on the L1
// chain), whose consensus path is proven.
//
// This is exposed as a free function rather than a method: the helper lives in
// its own realm, and gno forbids allocating a realm-defined struct in a
// different realm (the consuming scenario realm), so a bound object cannot be
// constructed at the call site.
func ProveConsensus(contractAddr types.H256, l2ClientId types.ClientId, l2Height uint64, l2ConsensusState []byte) (proof, root []byte) {
	consensusPath := types.ConsensusStatePath(l2ClientId, types.NewHeight(l2Height))
	valueHash := keccak256.Sum256(l2ConsensusState)
	value := valueHash[:]

	// Level 0 (iavl): proves value at the store-prefixed consensus key.
	key0 := makeStoreKey(contractAddr, consensusPath[:])
	iavlLeaf := iavlLeafOp()
	subroot0 := mustCalculate(&ics23.ExistenceProof{Key: key0, Value: value, Leaf: iavlLeaf})

	// Level 1 (tendermint): proves the iavl subroot at the module key.
	tmLeaf := ics23.TendermintSpec().LeafSpec
	root = mustCalculate(&ics23.ExistenceProof{Key: moduleKey, Value: subroot0, Leaf: tmLeaf})

	ep0 := encodeExistenceProof(key0, value, encodeLeafOp(iavlLeaf), nil)
	ep1 := encodeExistenceProof(moduleKey, subroot0, encodeLeafOp(tmLeaf), nil)
	proof = encodeMerkleProof(encodeCommitmentExist(ep0), encodeCommitmentExist(ep1))

	return proof, root
}

// ClientType is the cometbls client type string to register the L1 client under.
const ClientType = lc.ClientType

// SeededClientBytes returns the encoded (clientState, consensusState) bytes for
// an L1 cometbls client whose consensus root at l1Height equals root. Pass these
// to core.CreateClient from the scenario realm (so the relayer-gated call is
// made by the authorized caller, not this helper realm).
func SeededClientBytes(contractAddr types.H256, l1Height uint64, root []byte) (clientStateBytes, consensusStateBytes []byte) {
	// Launder the externally-stored inputs into fresh locals: the encoders below
	// convert/copy these, which gno rejects on values owned by another realm
	// (the calling scenario realm). make+copy produces realm-local bytes.
	var addr types.H256
	copy(addr[:], contractAddr[:])
	rootLocal := make([]byte, len(root))
	copy(rootLocal, root)

	clientState := &lc.ClientState{
		ChainID: "l1",
		// The seeded consensus timestamp is 1 (epoch), so the trusting period
		// must span up to "now" or Status() reports the client Expired and the
		// proof-verification path (getActiveClient) rejects it. A ~146-year
		// window keeps it Active under any realistic VM clock. Unbonding must
		// exceed trusting (ClientState.Validate), and clock drift must be
		// non-zero. None of these affect VerifyMembership, which is all this L1
		// is asked to do (consensus is seeded directly, never header-verified).
		TrustingPeriod:  1 << 62,
		UnbondingPeriod: 1 << 63,
		MaxClockDrift:   1 << 30,
		LatestHeight:    types.NewHeight(l1Height),
		ContractAddress: addr,
	}
	consensusState := &lc.ConsensusState{
		Timestamp:          1,
		Root:               lc.MerkleRoot{Hash: rootLocal},
		NextValidatorsHash: make([]byte, 32),
	}

	clientStateBytes, err := lc.EncodeClientState(clientState)
	if err != nil {
		panic(err)
	}
	consensusStateBytes, err = lc.EncodeConsensusState(consensusState)
	if err != nil {
		panic(err)
	}

	return clientStateBytes, consensusStateBytes
}

// NewLightClient is the core.ClientImpl constructor for the L1 cometbls client.
// Register it with core.RegisterClient(ClientType, cometbls.NewLightClient).
func NewLightClient(clientStateBytes, consensusStateBytes []byte) (lightclient.Interface, error) {
	clientState, err := lc.DecodeClientState(clientStateBytes)
	if err != nil {
		return nil, err
	}
	consensusState, err := lc.DecodeConsensusState(consensusStateBytes)
	if err != nil {
		return nil, err
	}

	return lc.NewCometblsLightClient(clientState, consensusState)
}

// iavlLeafOp returns the iavl leaf op with a real IAVL leaf header prefix
// (zigzag varints height=0, size=1, version=0 -> {0x00, 0x02, 0x00}). The
// IavlSpec's {0} prefix is only a HasPrefix sentinel; the L1 verifier parses
// these three varints, so the proof must carry the full header.
func iavlLeafOp() *ics23.LeafOp {
	spec := ics23.IavlSpec().LeafSpec

	return &ics23.LeafOp{
		Hash:         spec.Hash,
		PrehashKey:   spec.PrehashKey,
		PrehashValue: spec.PrehashValue,
		Length:       spec.Length,
		Prefix:       []byte{0x00, 0x02, 0x00},
	}
}

func mustCalculate(ep *ics23.ExistenceProof) []byte {
	root, err := ep.Calculate()
	if err != nil {
		panic(err)
	}

	return root
}
