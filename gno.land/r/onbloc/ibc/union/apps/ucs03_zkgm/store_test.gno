package ucs03_zkgm

import (
	"testing"

	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	types "gno.land/p/onbloc/ibc/union/types"
	tb "gno.land/p/onbloc/ibc/union/zkgm/tokenbucket"
)

func TestNewStore(t *testing.T) {
	s := NewStore()

	uassert.False(t, s.HasVoucher("ibc/missing"))
	uassert.True(t, s.RateLimitDisabled())

	_, ok := s.GetTokenOrigin("denom")
	uassert.False(t, ok)
	_, ok = s.GetChannelBalanceV2("key")
	uassert.False(t, ok)
	_, ok = s.GetMetadataImageOf("denom")
	uassert.False(t, ok)
	_, ok = s.GetForeignToken("denom")
	uassert.False(t, ok)
	_, ok = s.GetInFlightPacket("hash")
	uassert.False(t, ok)
	_, ok = s.GetTokenBucket("denom")
	uassert.False(t, ok)
	_, ok = s.GetVoucher("ibc/denom")
	uassert.False(t, ok)
	_, ok = s.GetReceiver("gno.land/r/receiver")
	uassert.False(t, ok)
}

func TestTokenOrigin(cur realm, t *testing.T) {
	s := NewStore()
	cases := []struct {
		name  string
		denom string
		path  *u256.Uint
	}{
		{"zero path", "ibc/zero", u256.Zero()},
		{"nonzero path", "ibc/nonzero", u256.NewUint(17)},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			s.SetTokenOrigin(0, cur, tc.denom, tc.path)
			got, ok := s.GetTokenOrigin(tc.denom)
			uassert.True(t, ok)
			uassert.True(t, got.Eq(tc.path))
		})
	}
}

func TestChannelBalanceV2(cur realm, t *testing.T) {
	s := NewStore()
	cases := []struct {
		name   string
		key    string
		amount *u256.Uint
		remove bool
	}{
		{"stores balance", "channel-a", u256.NewUint(10), false},
		{"removes balance", "channel-b", u256.NewUint(20), true},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			s.SetChannelBalanceV2(0, cur, tc.key, tc.amount)
			if tc.remove {
				s.RemoveChannelBalanceV2(0, cur, tc.key)
				_, ok := s.GetChannelBalanceV2(tc.key)
				uassert.False(t, ok)
				return
			}

			got, ok := s.GetChannelBalanceV2(tc.key)
			uassert.True(t, ok)
			uassert.True(t, got.Eq(tc.amount))
		})
	}
}

// AddLockedTokenAmount accumulates permanently-locked base-token escrow per denom. It
// stores the first lock, sums subsequent locks, treats a zero add as a no-op,
// reaches exactly 2^256-1 without tripping, and aborts on the overflow that
// would otherwise wrap the total below its prior value (breaking the proxy
// balance invariant). A fresh store and a distinct denom keep cases isolated.
func TestAddLockedTokenAmount(cur realm, t *testing.T) {
	maxU256 := func() *u256.Uint { return new(u256.Uint).SetAllOne() }

	cases := []struct {
		name      string
		seed      *u256.Uint // nil => no pre-existing entry
		add       *u256.Uint
		wantAbort bool
		wantTotal *u256.Uint
	}{
		{"first lock stores amount", nil, u256.NewUint(100), false, u256.NewUint(100)},
		{"accumulates locks", u256.NewUint(100), u256.NewUint(50), false, u256.NewUint(150)},
		{"zero add is noop", u256.NewUint(100), u256.NewUint(0), false, u256.NewUint(100)},
		{"sum to exactly max does not overflow", u256.Zero().Sub(maxU256(), u256.NewUint(7)), u256.NewUint(7), false, maxU256()},
		{"overflow aborts", maxU256(), u256.NewUint(1), true, maxU256()},
	}

	s := NewStore()
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			denom := "ulock/" + tc.name
			if tc.seed != nil {
				s.AddLockedTokenAmount(0, cur, denom, tc.seed)
			}

			if tc.wantAbort {
				uassert.AbortsContains(t, cur, ErrLockedTokenAmountOverflow, func(cur realm) {
					s.AddLockedTokenAmount(0, cur, denom, tc.add)
				})
			} else {
				s.AddLockedTokenAmount(0, cur, denom, tc.add)
			}

			got, ok := s.GetLockedTokenAmount(denom)
			uassert.True(t, ok)
			uassert.True(t, got.Eq(tc.wantTotal))
		})
	}
}

func TestMetadataImageOf(cur realm, t *testing.T) {
	s := NewStore()
	imageA := [32]byte{0x01, 0x02}
	imageB := [32]byte{0x0a, 0x0b}
	cases := []struct {
		name  string
		denom string
		image [32]byte
	}{
		{"stores first image", "ibc/image-a", imageA},
		{"stores second image", "ibc/image-b", imageB},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			s.SetMetadataImageOf(0, cur, tc.denom, tc.image)
			got, ok := s.GetMetadataImageOf(tc.denom)
			uassert.True(t, ok)
			uassert.True(t, got == tc.image)
		})
	}
}

func TestForeignToken(cur realm, t *testing.T) {
	s := NewStore()
	cases := []struct {
		name  string
		denom string
		token []byte
	}{
		{"stores text token", "ibc/foreign-a", []byte("uatom")},
		{"stores binary token", "ibc/foreign-b", []byte{0x00, 0x01, 0x02}},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			s.SetForeignToken(0, cur, tc.denom, tc.token)
			got, ok := s.GetForeignToken(tc.denom)
			uassert.True(t, ok)
			uassert.Equal(t, string(tc.token), string(got))
		})
	}
}

func TestInFlightPacket(cur realm, t *testing.T) {
	s := NewStore()
	cases := []struct {
		name   string
		hash   string
		packet types.Packet
		remove bool
	}{
		{"stores packet", "hash-a", types.NewPacket(1, 2, []byte("data-a"), 100), false},
		{"removes packet", "hash-b", types.NewPacket(3, 4, []byte("data-b"), 200), true},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			s.SetInFlightPacket(0, cur, tc.hash, tc.packet)
			if tc.remove {
				s.RemoveInFlightPacket(0, cur, tc.hash)
				_, ok := s.GetInFlightPacket(tc.hash)
				uassert.False(t, ok)
				return
			}

			got, ok := s.GetInFlightPacket(tc.hash)
			uassert.True(t, ok)
			uassert.Equal(t, uint32(tc.packet.SourceChannelId), uint32(got.SourceChannelId))
			uassert.Equal(t, uint32(tc.packet.DestinationChannelId), uint32(got.DestinationChannelId))
			uassert.Equal(t, string(tc.packet.Data), string(got.Data))
			uassert.Equal(t, uint64(tc.packet.TimeoutTimestamp), uint64(got.TimeoutTimestamp))
		})
	}
}

func TestTokenBucket(cur realm, t *testing.T) {
	s := NewStore()
	bucketA := mustTokenBucketForTest(t, 100, 5, 1)
	bucketB := mustTokenBucketForTest(t, 200, 10, 2)
	cases := []struct {
		name   string
		denom  string
		bucket *tb.TokenBucket
		remove bool
	}{
		{"stores bucket", "ibc/bucket-a", bucketA, false},
		{"removes bucket", "ibc/bucket-b", bucketB, true},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			s.SetTokenBucket(0, cur, tc.denom, tc.bucket)
			if tc.remove {
				s.RemoveTokenBucket(0, cur, tc.denom)
				_, ok := s.GetTokenBucket(tc.denom)
				uassert.False(t, ok)
				return
			}

			got, ok := s.GetTokenBucket(tc.denom)
			uassert.True(t, ok)
			uassert.True(t, got.Capacity.Eq(tc.bucket.Capacity))
			uassert.True(t, got.RefillRate.Eq(tc.bucket.RefillRate))
			uassert.True(t, got.LastRefill.Eq(tc.bucket.LastRefill))
		})
	}
}

func TestVoucherStore(cur realm, t *testing.T) {
	s := NewStore()
	token, ledger := newVoucherTokenForTest(cur, "Store Voucher", "SVOU")
	vou := NewVoucher(token, ledger, 0)

	uassert.False(t, s.HasVoucher("ibc/store-voucher"))
	s.SetVoucher(0, cur, "ibc/store-voucher", vou)

	got, ok := s.GetVoucher("ibc/store-voucher")
	uassert.True(t, ok)
	uassert.True(t, s.HasVoucher("ibc/store-voucher"))
	uassert.True(t, got == vou)
}

func TestStoreGetVoucherList(cur realm, t *testing.T) {
	s := NewStore()

	uassert.Equal(t, 0, len(s.GetVoucherList(0, 10)))

	cases := []struct {
		name       string
		denom      string
		tokenName  string
		symbol     string
		mintAmount int64
		wantSupply int64
	}{
		{"alpha voucher with balance", "ibc/store-list-a", "Alpha", "ALPHA", 42, 42},
		{"beta voucher with no mint yet", "ibc/store-list-b", "Beta", "BETA", 0, 0},
	}

	for _, tc := range cases {
		token, ledger := newVoucherTokenForTest(cur, tc.tokenName, tc.symbol)
		s.SetVoucher(0, cur, tc.denom, NewVoucher(token, ledger, 6))
		if tc.mintAmount > 0 {
			uassert.NoError(t, ledger.Mint(address(testutils.TestAddress("list-rx")), tc.mintAmount))
		}
	}

	got := s.GetVoucherList(0, len(cases))
	uassert.Equal(t, len(cases), len(got))

	byDenom := map[string]VoucherInfo{}
	for _, info := range got {
		byDenom[info.Denom] = info
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			info, ok := byDenom[tc.denom]
			uassert.True(t, ok)
			uassert.Equal(t, tc.tokenName, info.Name)
			uassert.Equal(t, tc.symbol, info.Symbol)
			uassert.Equal(t, tc.wantSupply, info.TotalSupply)
		})
	}
}

// GetVoucherList pages by offset/count in denom-sorted order (bptree's
// natural key order), since the vouchers tree only ever grows and an
// unbounded single call would let the response/gas cost grow with usage.
func TestStoreGetVoucherListPagination(cur realm, t *testing.T) {
	s := NewStore()

	denoms := []string{"ibc/page-a", "ibc/page-b", "ibc/page-c"}
	for _, denom := range denoms {
		token, ledger := newVoucherTokenForTest(cur, denom, "SYM")
		s.SetVoucher(0, cur, denom, NewVoucher(token, ledger, 6))
	}

	cases := []struct {
		name       string
		offset     int
		count      int
		wantDenoms []string
	}{
		{"first page", 0, 2, []string{"ibc/page-a", "ibc/page-b"}},
		{"second page", 2, 2, []string{"ibc/page-c"}},
		{"offset past end returns empty", 3, 2, []string{}},
		{"zero count returns empty", 0, 0, []string{}},
		{"count beyond remaining is clamped", 0, 10, []string{"ibc/page-a", "ibc/page-b", "ibc/page-c"}},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := s.GetVoucherList(tc.offset, tc.count)
			uassert.Equal(t, len(tc.wantDenoms), len(got))
			for i, denom := range tc.wantDenoms {
				uassert.Equal(t, denom, got[i].Denom)
			}
		})
	}
}

func TestReceiver(cur realm, t *testing.T) {
	s := NewStore()
	cases := []struct {
		name     string
		path     string
		receiver *dummyReceiver
	}{
		{"receiver a", "gno.land/r/receiver/a", &dummyReceiver{}},
		{"receiver b", "gno.land/r/receiver/b", &dummyReceiver{}},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			s.SetReceiver(0, cur, tc.path, tc.receiver)
			got, ok := s.GetReceiver(tc.path)
			uassert.True(t, ok)
			uassert.True(t, got == tc.receiver)
		})
	}
}

func TestRateLimitDisabled(cur realm, t *testing.T) {
	s := NewStore()
	cases := []struct {
		name     string
		disabled bool
	}{
		{"enables rate limit", false},
		{"disables rate limit", true},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			s.SetRateLimitDisabled(0, cur, tc.disabled)
			uassert.Equal(t, tc.disabled, s.RateLimitDisabled())
		})
	}
}

func TestStore_MutationsRejectSpoofedRealm(cur realm, t *testing.T) {
	s := NewStore()
	token, ledger := newVoucherTokenForTest(cur, "Spoof Voucher", "SPF")
	vou := NewVoucher(token, ledger, 0)
	bucket := mustTokenBucketForTest(t, 100, 10, 1)
	packet := types.NewPacket(1, 2, []byte("parent"), 100)
	spoofedRealm := cur.Previous()

	cases := []struct {
		name string
		run  func()
	}{
		{"set token origin", func() { s.SetTokenOrigin(0, spoofedRealm, "ibc/spoof-origin", u256.NewUint(1)) }},
		{"set channel balance", func() { s.SetChannelBalanceV2(0, spoofedRealm, "spoof-balance", u256.NewUint(2)) }},
		{"remove channel balance", func() { s.RemoveChannelBalanceV2(0, spoofedRealm, "spoof-balance") }},
		{"set metadata image", func() { s.SetMetadataImageOf(0, spoofedRealm, "ibc/spoof-image", [32]byte{0x01}) }},
		{"set foreign token", func() { s.SetForeignToken(0, spoofedRealm, "ibc/spoof-foreign", []byte("utoken")) }},
		{"set inflight packet", func() { s.SetInFlightPacket(0, spoofedRealm, "spoof-packet", packet) }},
		{"remove inflight packet", func() { s.RemoveInFlightPacket(0, spoofedRealm, "spoof-packet") }},
		{"set token bucket", func() { s.SetTokenBucket(0, spoofedRealm, "ibc/spoof-bucket", bucket) }},
		{"remove token bucket", func() { s.RemoveTokenBucket(0, spoofedRealm, "ibc/spoof-bucket") }},
		{"set voucher", func() { s.SetVoucher(0, spoofedRealm, "ibc/spoof-voucher", vou) }},
		{"set receiver", func() { s.SetReceiver(0, spoofedRealm, "gno.land/r/spoof/receiver", &dummyReceiver{}) }},
		{"set rate limit disabled", func() { s.SetRateLimitDisabled(0, spoofedRealm, false) }},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			uassert.AbortsContains(t, cur, ErrSpoofedRealm, func(cur realm) {
				tc.run()
			})
		})
	}
}

func TestStore_RemoveMissingEntries(cur realm, t *testing.T) {
	s := NewStore()
	cases := []struct {
		name   string
		remove func()
		exists func() bool
	}{
		{
			name:   "channel balance",
			remove: func() { s.RemoveChannelBalanceV2(0, cur, "missing-channel-balance") },
			exists: func() bool {
				_, ok := s.GetChannelBalanceV2("missing-channel-balance")
				return ok
			},
		},
		{
			name:   "inflight packet",
			remove: func() { s.RemoveInFlightPacket(0, cur, "missing-inflight") },
			exists: func() bool {
				_, ok := s.GetInFlightPacket("missing-inflight")
				return ok
			},
		},
		{
			name:   "token bucket",
			remove: func() { s.RemoveTokenBucket(0, cur, "missing-token-bucket") },
			exists: func() bool {
				_, ok := s.GetTokenBucket("missing-token-bucket")
				return ok
			},
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			uassert.NotAborts(t, cur, func() {
				tc.remove()
			})
			uassert.False(t, tc.exists())
		})
	}
}

func mustTokenBucketForTest(t *testing.T, capacity uint64, refillRate uint64, now uint64) *tb.TokenBucket {
	bucket, err := tb.New(u256.NewUint(capacity), u256.NewUint(refillRate), u256.NewUint(now))
	if err != nil {
		t.Fatal(err)
	}

	return bucket
}
