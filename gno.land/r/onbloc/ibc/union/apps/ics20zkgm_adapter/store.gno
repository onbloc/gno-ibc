package ics20zkgm_adapter

import (
	"gno.land/p/nt/bptree/v0"
	types "gno.land/p/onbloc/ibc/union/types"
)

// DenomConfig is the admin-registered, per-ICS20-base-denom data needed to
// build an outbound ZKGM TokenOrderV2 for the forward (AtomOne -> EVM) path
// (see v1/impl.gno OnTransferRecv). Keyed by the ICS20 base denom
// (transfer.Denom.Base, e.g. "uatom") — see RegisterDenom in admin.gno.
//
// QuoteToken and Metadata must be computed off-chain (this realm cannot call
// the EVM predictWrappedTokenV2 view live) and must be byte-identical to what
// apps/ucs03_zkgm/v1 decodes/verifies on send. BaseToken is NOT stored here:
// it is derived at call time from the recv'd Denom (denom.HashHex(), the same
// grc20reg slug apps/transfer registered the voucher under), so it never goes
// stale relative to the actual voucher registration.
type DenomConfig struct {
	// ZkgmChannelId is the destination ZKGM channel routing toward the target
	// EVM chain via Union.
	ZkgmChannelId types.ChannelId
	// QuoteToken is the predicted 20-byte ZkgmERC20 address on the EVM chain,
	// computed off-chain via predictWrappedTokenV2(path, destChannel,
	// baseToken, keccak256(Metadata)). See CLAUDE.md "quote_token must be the
	// predicted ZkgmERC20 address".
	QuoteToken []byte
	// Metadata is the ABI-encoded z.TokenMetadata (Implementation + Initializer)
	// used to derive QuoteToken above; must be byte-identical to what was fed
	// into the off-chain prediction. Initializer's decimals field must be 0 to
	// match the Gno-side voucher (apps/transfer always mints vouchers with 0
	// decimals; see v1/impl.gno's OnTransferRecv doc comment).
	Metadata []byte
}

// NewDenomConfig constructs a DenomConfig. Foreign realms (e.g. v1's impl)
// must go through this instead of a struct literal — DenomConfig is defined
// here, and allocating it directly from another realm panics with "cannot
// allocate DenomConfig in realm ...".
func NewDenomConfig(zkgmChannelId types.ChannelId, quoteToken, metadata []byte) DenomConfig {
	return DenomConfig{
		ZkgmChannelId: zkgmChannelId,
		QuoteToken:    quoteToken,
		Metadata:      metadata,
	}
}

// PendingForward is what OnTransferRecv records right before calling
// zkgm.Send, keyed by the outbound ZKGM packet's commitment hash (the same
// key zkgm.GetSendResult/ClearSendResult use), so that once the packet's
// ack/timeout result is known, ResolveForward knows which original ICS20
// packet's deferred acknowledgement to resolve via the installed
// TransferAckResolver.
type PendingForward struct {
	// SourceClient is the ICS20 clientID the original AtomOne packet arrived
	// on. Together with Sequence, this is the same correlation pair
	// OnTransferRecv itself was called with, and what TransferAckResolver
	// resolves against — no new identifier is introduced.
	SourceClient string
	// Sequence is the original AtomOne packet's sequence on SourceClient.
	Sequence uint64
}

// NewPendingForward constructs a PendingForward. Foreign realms (e.g. v1's
// impl) must go through this instead of a struct literal — see
// NewDenomConfig's doc comment for why.
func NewPendingForward(sourceClient string, sequence uint64) PendingForward {
	return PendingForward{
		SourceClient: sourceClient,
		Sequence:     sequence,
	}
}

// Store is the proxy-owned persistent state, injected into the impl via
// RegisterImpl/UpdateImpl so it survives impl upgrades (mirrors
// apps/ucs03_zkgm/store.gno's Store).
type Store struct {
	denomConfigs    *bptree.BPTree // ICS20 base denom -> DenomConfig
	pendingForwards *bptree.BPTree // packetHash -> PendingForward
}

func NewStore() *Store {
	return &Store{
		denomConfigs:    bptree.NewBPTree32(),
		pendingForwards: bptree.NewBPTree32(),
	}
}

// SetDenomConfig registers or replaces the forward-path config for baseDenom.
func (s *Store) SetDenomConfig(_ int, rlm realm, baseDenom string, cfg DenomConfig) {
	assertIsRlmCurrent(0, rlm)

	s.denomConfigs.Set(baseDenom, cfg)
}

// RemoveDenomConfig clears the forward-path config for baseDenom.
func (s *Store) RemoveDenomConfig(_ int, rlm realm, baseDenom string) {
	assertIsRlmCurrent(0, rlm)

	s.denomConfigs.Remove(baseDenom)
}

// GetDenomConfig returns the forward-path config for baseDenom, if registered.
func (s *Store) GetDenomConfig(baseDenom string) (DenomConfig, bool) {
	v, found := s.denomConfigs.Get(baseDenom)
	if !found {
		return DenomConfig{}, false
	}

	return v.(DenomConfig), true
}

// HasDenomConfig reports whether baseDenom has a registered forward-path config.
func (s *Store) HasDenomConfig(baseDenom string) bool {
	return s.denomConfigs.Has(baseDenom)
}

// SetPendingForward records a forward attempt's correlation info, keyed by
// the outbound ZKGM packet's commitment hash.
func (s *Store) SetPendingForward(_ int, rlm realm, packetHash string, info PendingForward) {
	assertIsRlmCurrent(0, rlm)

	s.pendingForwards.Set(packetHash, info)
}

// GetPendingForward returns the correlation info recorded for a packet hash, if any.
func (s *Store) GetPendingForward(packetHash string) (PendingForward, bool) {
	v, found := s.pendingForwards.Get(packetHash)
	if !found {
		return PendingForward{}, false
	}

	return v.(PendingForward), true
}

// RemovePendingForward clears a resolved (or no-longer-relevant) pending
// forward record.
func (s *Store) RemovePendingForward(_ int, rlm realm, packetHash string) {
	assertIsRlmCurrent(0, rlm)

	s.pendingForwards.Remove(packetHash)
}
