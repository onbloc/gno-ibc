package impl

import (
	types "gno.land/p/onbloc/ibc/union/types"

	u256 "gno.land/p/gnoswap/uint256"
	z "gno.land/p/onbloc/ibc/union/zkgm"
	tb "gno.land/p/onbloc/ibc/union/zkgm/tokenbucket"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
)

// mockStore is an in-memory zkgm.IStore used by unit tests.
//
// Unlike the production store, which is owned by the proxy realm, mockStore is
// backed by test-owned maps and can be mutated directly by injected test code.
type mockStore struct {
	tokenOrigin       map[string]*u256.Uint
	channelBalanceV2  map[string]*u256.Uint
	metadataImageOf   map[string][32]byte
	foreignToken      map[string][]byte
	inFlightPacket    map[string]types.Packet
	tokenBucket       map[string]*tb.TokenBucket
	vouchers          map[string]*zkgm.Voucher
	receivers         map[string]z.Zkgmable
	rateLimitDisabled bool
}

var _ zkgm.IStore = (*mockStore)(nil)

func newMockStore() *mockStore {
	return &mockStore{
		tokenOrigin:      map[string]*u256.Uint{},
		channelBalanceV2: map[string]*u256.Uint{},
		metadataImageOf:  map[string][32]byte{},
		foreignToken:     map[string][]byte{},
		inFlightPacket:   map[string]types.Packet{},
		tokenBucket:      map[string]*tb.TokenBucket{},
		vouchers:         map[string]*zkgm.Voucher{},
		receivers:        map[string]z.Zkgmable{},
		// Match NewStore: rate limiting is opt-in (disabled by default).
		rateLimitDisabled: true,
	}
}

func (m *mockStore) SetTokenOrigin(_ int, rlm realm, denom string, path *u256.Uint) {
	m.tokenOrigin[denom] = path
}

func (m *mockStore) GetTokenOrigin(denom string) (*u256.Uint, bool) {
	v, ok := m.tokenOrigin[denom]
	return v, ok
}

func (m *mockStore) SetChannelBalanceV2(_ int, rlm realm, key string, amount *u256.Uint) {
	m.channelBalanceV2[key] = amount
}

func (m *mockStore) RemoveChannelBalanceV2(_ int, rlm realm, key string) {
	delete(m.channelBalanceV2, key)
}

func (m *mockStore) GetChannelBalanceV2(key string) (*u256.Uint, bool) {
	v, ok := m.channelBalanceV2[key]
	return v, ok
}

func (m *mockStore) SetMetadataImageOf(_ int, rlm realm, denom string, image [32]byte) {
	m.metadataImageOf[denom] = image
}

func (m *mockStore) GetMetadataImageOf(denom string) ([32]byte, bool) {
	v, ok := m.metadataImageOf[denom]
	return v, ok
}

func (m *mockStore) SetForeignToken(_ int, rlm realm, denom string, token []byte) {
	m.foreignToken[denom] = token
}

func (m *mockStore) GetForeignToken(denom string) ([]byte, bool) {
	v, ok := m.foreignToken[denom]
	return v, ok
}

func (m *mockStore) SetInFlightPacket(_ int, rlm realm, packetHash string, parent types.Packet) {
	m.inFlightPacket[packetHash] = parent
}

func (m *mockStore) GetInFlightPacket(packetHash string) (types.Packet, bool) {
	v, ok := m.inFlightPacket[packetHash]
	return v, ok
}

func (m *mockStore) RemoveInFlightPacket(_ int, rlm realm, packetHash string) {
	delete(m.inFlightPacket, packetHash)
}

func (m *mockStore) SetTokenBucket(_ int, rlm realm, denom string, bucket *tb.TokenBucket) {
	m.tokenBucket[denom] = bucket
}

func (m *mockStore) GetTokenBucket(denom string) (*tb.TokenBucket, bool) {
	v, ok := m.tokenBucket[denom]
	return v, ok
}

func (m *mockStore) RemoveTokenBucket(_ int, rlm realm, denom string) {
	delete(m.tokenBucket, denom)
}

func (m *mockStore) SetVoucher(_ int, rlm realm, ibcDenom string, v *zkgm.Voucher) {
	m.vouchers[ibcDenom] = v
}

func (m *mockStore) GetVoucher(ibcDenom string) (*zkgm.Voucher, bool) {
	v, ok := m.vouchers[ibcDenom]
	return v, ok
}

func (m *mockStore) HasVoucher(ibcDenom string) bool {
	_, ok := m.vouchers[ibcDenom]
	return ok
}

func (m *mockStore) SetReceiver(_ int, rlm realm, path string, receiver z.Zkgmable) {
	m.receivers[path] = receiver
}

func (m *mockStore) GetReceiver(path string) (z.Zkgmable, bool) {
	v, ok := m.receivers[path]
	return v, ok
}

func (m *mockStore) SetRateLimitDisabled(_ int, rlm realm, disabled bool) {
	m.rateLimitDisabled = disabled
}

func (m *mockStore) RateLimitDisabled() bool {
	return m.rateLimitDisabled
}
