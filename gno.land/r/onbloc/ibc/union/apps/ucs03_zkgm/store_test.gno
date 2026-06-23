package zkgm

import (
	"testing"

	u256 "gno.land/p/gnoswap/uint256"
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
	vou := NewVoucher(0, cur, token, ledger)

	uassert.False(t, s.HasVoucher("ibc/store-voucher"))
	s.SetVoucher(0, cur, "ibc/store-voucher", vou)

	got, ok := s.GetVoucher("ibc/store-voucher")
	uassert.True(t, ok)
	uassert.True(t, s.HasVoucher("ibc/store-voucher"))
	uassert.True(t, got == vou)
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

func mustTokenBucketForTest(t *testing.T, capacity uint64, refillRate uint64, now uint64) *tb.TokenBucket {
	bucket, err := tb.New(u256.NewUint(capacity), u256.NewUint(refillRate), u256.NewUint(now))
	if err != nil {
		t.Fatal(err)
	}

	return bucket
}
