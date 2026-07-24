package ucs03_zkgm

import (
	"sort"

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
	tokenOrigin        map[string]*u256.Uint
	channelBalanceV2   map[string]*u256.Uint
	metadataImageOf    map[string][32]byte
	foreignToken       map[string][]byte
	inFlightPacket     map[string]types.Packet
	tokenBucket        map[string]*tb.TokenBucket
	vouchers           map[string]*zkgm.Voucher
	lockedTokenAmounts map[string]*u256.Uint
	receivers          map[string]z.Zkgmable
	nativeEscrowTotal  map[string]*u256.Uint
	rateLimitDisabled  bool
}

var _ zkgm.IStore = (*mockStore)(nil)

func newMockStore() *mockStore {
	return &mockStore{
		tokenOrigin:        map[string]*u256.Uint{},
		channelBalanceV2:   map[string]*u256.Uint{},
		metadataImageOf:    map[string][32]byte{},
		foreignToken:       map[string][]byte{},
		inFlightPacket:     map[string]types.Packet{},
		tokenBucket:        map[string]*tb.TokenBucket{},
		vouchers:           map[string]*zkgm.Voucher{},
		lockedTokenAmounts: map[string]*u256.Uint{},
		receivers:          map[string]z.Zkgmable{},
		nativeEscrowTotal:  map[string]*u256.Uint{},
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

// GetVoucherList paginates over denoms in sorted order to match the real
// Store's bptree-ordered iteration, so pagination tests behave the same
// against either store.
func (m *mockStore) GetVoucherList(offset, count int) []zkgm.VoucherInfo {
	denoms := make([]string, 0, len(m.vouchers))
	for denom := range m.vouchers {
		denoms = append(denoms, denom)
	}
	sort.Strings(denoms)

	list := []zkgm.VoucherInfo{}
	if offset < 0 || offset >= len(denoms) || count <= 0 {
		return list
	}

	end := offset + count
	if end > len(denoms) {
		end = len(denoms)
	}

	for _, denom := range denoms[offset:end] {
		voucher := m.vouchers[denom]
		list = append(list, zkgm.NewVoucherInfo(
			denom,
			voucher.Token().GetName(),
			voucher.Token().GetSymbol(),
			voucher.OriginDecimals(),
			uint8(voucher.Token().GetDecimals()),
			voucher.Token().TotalSupply(),
		))
	}

	return list
}

func (m *mockStore) HasVoucher(ibcDenom string) bool {
	_, ok := m.vouchers[ibcDenom]
	return ok
}

// GetVoucherSize returns the total number of registered vouchers.
func (m *mockStore) GetVoucherSize() int {
	return len(m.vouchers)
}

func (m *mockStore) AddLockedTokenAmount(_ int, rlm realm, denom string, amount *u256.Uint) {
	total := u256.Zero()
	if cur, ok := m.lockedTokenAmounts[denom]; ok {
		total.Set(cur)
	}
	total.Add(total, amount)
	m.lockedTokenAmounts[denom] = total
}

func (m *mockStore) GetLockedTokenAmount(denom string) (*u256.Uint, bool) {
	v, ok := m.lockedTokenAmounts[denom]
	return v, ok
}

func (m *mockStore) AddNativeEscrowTotal(_ int, rlm realm, denom string, amount *u256.Uint) {
	total := u256.Zero()
	if cur, ok := m.nativeEscrowTotal[denom]; ok {
		total.Set(cur)
	}

	total, overflow := u256.Zero().AddOverflow(total, amount)
	if overflow {
		panic(zkgm.ErrNativeEscrowOverflow)
	}

	m.nativeEscrowTotal[denom] = total
}

func (m *mockStore) SubNativeEscrowTotal(_ int, rlm realm, denom string, amount *u256.Uint) {
	cur, ok := m.nativeEscrowTotal[denom]
	if !ok || cur.Cmp(amount) < 0 {
		panic(zkgm.ErrNativeEscrowUnderflow)
	}

	total, underflow := u256.Zero().SubOverflow(cur, amount)
	if underflow {
		panic(zkgm.ErrNativeEscrowUnderflow)
	}

	m.nativeEscrowTotal[denom] = total
}

func (m *mockStore) GetNativeEscrowTotal(denom string) (*u256.Uint, bool) {
	v, ok := m.nativeEscrowTotal[denom]
	return v, ok
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
