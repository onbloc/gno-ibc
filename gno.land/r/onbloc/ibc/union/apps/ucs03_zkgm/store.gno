package zkgm

import (
	types "gno.land/p/onbloc/ibc/union/types"

	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/bptree/v0"
	z "gno.land/p/onbloc/ibc/union/zkgm"
	tb "gno.land/p/onbloc/ibc/union/zkgm/tokenbucket"
)

// store is the proxy-owned singleton holding all persistent domain state. It is
// the dependency injected into the implementation realm: the impl receives this
// pointer and mutates state through the SetXXX(_ int, rlm realm, ...) methods,
// whose trailing realm token carries the caller frame so the write satisfies the
// interrealm borrow rule. Reads use plain getters (no mutation, no realm token).
//
// Mapping to the reference CosmWasm contract (state.rs):
//
//	tokenOrigin        <- TOKEN_ORIGIN          Map<denom, U256>
//	channelBalanceV2   <- CHANNEL_BALANCE_V2    Map<(channel,path,base,quote), U256>
//	metadataImageOf    <- METADATA_IMAGE_OF     Map<denom, H256>
//	hashToForeignToken <- HASH_TO_FOREIGN_TOKEN Map<denom, Bytes>
//	inFlightPacket     <- IN_FLIGHT_PACKET      Map<packetHash, Packet>
//	tokenBucket        <- TOKEN_BUCKET          Map<denom, TokenBucket>
//	rateLimitDisabled  <- CONFIG.rate_limit_disabled
//
// CONFIG.{admin,ibc_host} are not duplicated here: they are sourced from core.
// The CosmWasm code_id fields (token_minter/dummy/cw_account) and the
// transaction-scratch items (EXECUTING_PACKET, EXECUTION_ACK, MARKET_MAKER, ...)
// are intentionally omitted: gno calls are synchronous, so that data is carried
// as parameters/locals instead of persisted across submessage hops.
var store *Store

// paused is a proxy-level gate checked by the App receivers before delegating to
// the impl. It is governance state, not impl-visible state, so it lives on the
// proxy package rather than inside the injected Store.
var paused bool

func init() {
	store = NewStore()
}

type Store struct {
	tokenOrigin        *bptree.BPTree // denom -> *u256.Uint  (mint path)
	channelBalanceV2   *bptree.BPTree // key   -> *u256.Uint  (escrow balance)
	metadataImageOf    *bptree.BPTree // denom -> [32]byte
	hashToForeignToken *bptree.BPTree // denom -> []byte
	inFlightPacket     *bptree.BPTree // packetHash -> types.Packet (parent)
	tokenBucket        *bptree.BPTree // denom -> *tb.TokenBucket
	vouchers           *bptree.BPTree // ibcDenom -> *Voucher
	receivers          *bptree.BPTree // pkgPath -> z.Zkgmable
	lockedNative       *bptree.BPTree // denom -> *u256.Uint (permanently locked native)
	rateLimitDisabled  bool
}

func NewStore() *Store {
	return &Store{
		tokenOrigin:        bptree.NewBPTree32(),
		channelBalanceV2:   bptree.NewBPTree32(),
		metadataImageOf:    bptree.NewBPTree32(),
		hashToForeignToken: bptree.NewBPTree32(),
		inFlightPacket:     bptree.NewBPTree32(),
		tokenBucket:        bptree.NewBPTree32(),
		vouchers:           bptree.NewBPTree32(),
		receivers:          bptree.NewBPTree32(),
		lockedNative:       bptree.NewBPTree32(),
		// Rate limiting is opt-in: enabled per-denom by an admin who first
		// configures a token bucket (see SetBucketConfig). With it enabled, a denom
		// without a bucket is rejected (union TokenBucketIsAbsent), so it must stay
		// disabled by default to avoid bricking every unconfigured denom.
		rateLimitDisabled: true,
	}
}

// SetTokenOrigin records the mint path for a wrapped denom.
func (s *Store) SetTokenOrigin(_ int, rlm realm, denom string, path *u256.Uint) {
	if !rlm.IsCurrent() {
		panic(ErrSpoofedRealm)
	}

	pathClone := u256.Zero().Set(path).Clone()

	s.tokenOrigin.Set(denom, pathClone)
}

// GetTokenOrigin returns the recorded mint path for a denom.
func (s *Store) GetTokenOrigin(denom string) (*u256.Uint, bool) {
	v, ok := s.tokenOrigin.Get(denom)
	if !ok {
		return nil, false
	}

	return v.(*u256.Uint), true
}

// SetChannelBalanceV2 stores the escrow balance for a channel-balance key.
func (s *Store) SetChannelBalanceV2(_ int, rlm realm, key string, amount *u256.Uint) {
	if !rlm.IsCurrent() {
		panic(ErrSpoofedRealm)
	}

	calculatedAmount := u256.Zero().Set(amount).Clone()

	s.channelBalanceV2.Set(key, calculatedAmount)
}

// RemoveChannelBalanceV2 clears a drained channel-balance entry.
func (s *Store) RemoveChannelBalanceV2(_ int, rlm realm, key string) {
	if !rlm.IsCurrent() {
		panic(ErrSpoofedRealm)
	}

	s.channelBalanceV2.Remove(key)
}

// GetChannelBalanceV2 returns the escrow balance for a key.
func (s *Store) GetChannelBalanceV2(key string) (*u256.Uint, bool) {
	v, ok := s.channelBalanceV2.Get(key)
	if !ok {
		return nil, false
	}

	return v.(*u256.Uint), true
}

// AddLockedNative records native escrow that has been permanently locked by a
// burn-address settlement. gno cannot destroy native supply, so a "burned"
// native stays in the proxy escrow account; the burn decrements its channel
// balance (removing it from the spendable escrow pool), and this counter tracks
// the locked total per denom so the coins are accounted rather than left as an
// orphaned surplus. It mirrors the transfer app's totalEscrow-style accounting
// and has no union counterpart (union burns the supply outright). The invariant
// preserved is: proxy native balance == sum(channelBalanceV2) + sum(lockedNative).
func (s *Store) AddLockedNative(_ int, rlm realm, denom string, amount *u256.Uint) {
	if !rlm.IsCurrent() {
		panic(ErrSpoofedRealm)
	}

	total := u256.Zero()
	if cur, ok := s.lockedNative.Get(denom); ok {
		total.Set(cur.(*u256.Uint))
	}

	total.Add(total, amount)

	s.lockedNative.Set(denom, total.Clone())
}

// GetLockedNative returns the total native permanently locked for a denom.
func (s *Store) GetLockedNative(denom string) (*u256.Uint, bool) {
	v, ok := s.lockedNative.Get(denom)
	if !ok {
		return nil, false
	}

	return v.(*u256.Uint), true
}

// SetMetadataImageOf records a wrapped denom's metadata image.
func (s *Store) SetMetadataImageOf(_ int, rlm realm, denom string, image [32]byte) {
	if !rlm.IsCurrent() {
		panic(ErrSpoofedRealm)
	}

	s.metadataImageOf.Set(denom, image)
}

// GetMetadataImageOf returns a wrapped denom's metadata image.
func (s *Store) GetMetadataImageOf(denom string) ([32]byte, bool) {
	v, ok := s.metadataImageOf.Get(denom)
	if !ok {
		return [32]byte{}, false
	}

	return v.([32]byte), true
}

// SetForeignToken records the origin token bytes for a wrapped denom.
func (s *Store) SetForeignToken(_ int, rlm realm, denom string, token []byte) {
	if !rlm.IsCurrent() {
		panic(ErrSpoofedRealm)
	}

	s.hashToForeignToken.Set(denom, token)
}

// GetForeignToken returns the origin token bytes for a wrapped denom.
func (s *Store) GetForeignToken(denom string) ([]byte, bool) {
	v, ok := s.hashToForeignToken.Get(denom)
	if !ok {
		return nil, false
	}

	return v.([]byte), true
}

// SetInFlightPacket records the parent packet awaiting a forwarded child.
func (s *Store) SetInFlightPacket(_ int, rlm realm, packetHash string, parent types.Packet) {
	if !rlm.IsCurrent() {
		panic(ErrSpoofedRealm)
	}

	s.inFlightPacket.Set(packetHash, parent)
}

// GetInFlightPacket returns the parent packet for a forwarded-child hash.
func (s *Store) GetInFlightPacket(packetHash string) (types.Packet, bool) {
	v, ok := s.inFlightPacket.Get(packetHash)
	if !ok {
		return types.Packet{}, false
	}

	return v.(types.Packet), true
}

// RemoveInFlightPacket clears a resolved forwarded-child entry.
func (s *Store) RemoveInFlightPacket(_ int, rlm realm, packetHash string) {
	if !rlm.IsCurrent() {
		panic(ErrSpoofedRealm)
	}

	s.inFlightPacket.Remove(packetHash)
}

// SetTokenBucket stores the rate-limit bucket for a denom.
func (s *Store) SetTokenBucket(_ int, rlm realm, denom string, bucket *tb.TokenBucket) {
	if !rlm.IsCurrent() {
		panic(ErrSpoofedRealm)
	}

	s.tokenBucket.Set(denom, bucket)
}

// GetTokenBucket returns the rate-limit bucket for a denom.
func (s *Store) GetTokenBucket(denom string) (*tb.TokenBucket, bool) {
	v, ok := s.tokenBucket.Get(denom)
	if !ok {
		return nil, false
	}

	return v.(*tb.TokenBucket), true
}

// RemoveTokenBucket clears a denom's rate-limit bucket.
func (s *Store) RemoveTokenBucket(_ int, rlm realm, denom string) {
	if !rlm.IsCurrent() {
		panic(ErrSpoofedRealm)
	}

	s.tokenBucket.Remove(denom)
}

// SetVoucher stores the wrapped voucher for an ibc denom.
func (s *Store) SetVoucher(_ int, rlm realm, ibcDenom string, v *Voucher) {
	if !rlm.IsCurrent() {
		panic(ErrSpoofedRealm)
	}

	s.vouchers.Set(ibcDenom, v)
}

// GetVoucher returns the wrapped voucher for an ibc denom.
func (s *Store) GetVoucher(ibcDenom string) (*Voucher, bool) {
	v, ok := s.vouchers.Get(ibcDenom)
	if !ok {
		return nil, false
	}

	return v.(*Voucher), true
}

// HasVoucher reports whether a voucher exists for an ibc denom.
func (s *Store) HasVoucher(ibcDenom string) bool {
	return s.vouchers.Has(ibcDenom)
}

// SetReceiver registers a Zkgmable callback target at a package path.
func (s *Store) SetReceiver(_ int, rlm realm, path string, receiver z.Zkgmable) {
	if !rlm.IsCurrent() {
		panic(ErrSpoofedRealm)
	}

	s.receivers.Set(path, receiver)
}

// GetReceiver returns the callback target registered at a package path.
func (s *Store) GetReceiver(path string) (z.Zkgmable, bool) {
	r, ok := s.receivers.Get(path)
	if !ok {
		return nil, false
	}

	return r.(z.Zkgmable), true
}

// SetRateLimitDisabled toggles the global rate-limit kill switch.
func (s *Store) SetRateLimitDisabled(_ int, rlm realm, disabled bool) {
	if !rlm.IsCurrent() {
		panic(ErrSpoofedRealm)
	}

	s.rateLimitDisabled = disabled
}

// RateLimitDisabled reports whether rate limiting is globally disabled.
func (s *Store) RateLimitDisabled() bool {
	return s.rateLimitDisabled
}
