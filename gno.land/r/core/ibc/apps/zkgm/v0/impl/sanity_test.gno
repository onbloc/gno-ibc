package impl

import (
	"chain"
	"testing"

	"gno.land/p/aib/ibc/types"
	z "gno.land/p/gnoswap/ibc/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/uassert/v0"

	zkgm "gno.land/r/gnoswap/ibc/apps/zkgm"
	"gno.land/r/gnoswap/ibc/apps/zkgm/testing/mock"
)

func TestSanityOriginCallerInDispatch(cur realm, t *testing.T) {
	mock.Reset(cross)
	mock.SetCaptureOrigin(cross, true)
	const origin = "g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsx"
	testing.SetOriginCaller(origin)

	res, err := (&ZkgmV0{}).executeCall(zkgm.RecvRequest{
		SourceClient:      "client-a",
		DestinationClient: "client-b",
		Caller:            origin,
		Relayer:           []byte(origin),
	}, u256.NewUint(7), z.Call{
		Sender:           []byte("sender"),
		ContractAddress:  []byte(mockReceiverPath),
		ContractCalldata: []byte("calldata"),
	})
	uassert.NoError(t, err)
	uassert.True(t, res.Status == types.PacketStatus_Success)

	envCaller := mock.LastCaller(cross)
	originSeen := mock.LastOriginCaller(cross)
	t.Logf("env.Caller        = %q", envCaller)
	t.Logf("OriginCaller seen = %q", originSeen)

	uassert.Equal(t, origin, envCaller)

	uassert.Equal(t, origin, originSeen)
}

func TestSanityEqualBytesReadonlyACK(t *testing.T) {
	a := z.ACK_ERR_ONLY_MAKER
	b := []byte{0xDE, 0xAD, 0xC0, 0xDE}
	uassert.True(t, equalBytes(a, b))
	uassert.False(t, equalBytes(a, []byte{0x00, 0x00, 0x00, 0x00}))
}

func TestSanityEncodeBatchAckWithReadonly(t *testing.T) {
	acks := [][]byte{
		cloneBytes(z.ACK_ERR_ONLY_MAKER),
		z.ACK_ERR_ONLY_MAKER,
		[]byte("normal"),
	}
	bz, err := z.EncodeBatchAck(z.BatchAck{Acknowledgements: acks})
	uassert.NoError(t, err)
	uassert.True(t, len(bz) > 0)
}

func TestSanityU256ArithmeticMutates(t *testing.T) {
	a := u256.NewUint(7)
	b := u256.NewUint(3)
	beforeA := a.Dec()

	c := new(u256.Uint).Add(a, b)
	t.Logf("after new.Add(a,b): a=%s c=%s (expect a=7 unchanged)", a.Dec(), c.Dec())
	uassert.Equal(t, beforeA, a.Dec())

	a.Add(a, b)
	t.Logf("after a.Add(a,b): a=%s (mutating form)", a.Dec())
	uassert.Equal(t, "10", a.Dec())

	d := new(u256.Uint).Set(b)
	t.Logf("after new.Set(b): b=%s d=%s", b.Dec(), d.Dec())
	uassert.Equal(t, "3", b.Dec())
	uassert.Equal(t, "3", d.Dec())
}

func TestSanityU256BytesPure(t *testing.T) {
	a := u256.NewUint(7)
	before := a.Dec()
	bz := z.Uint256ToBytes32(a)
	_ = bz
	uassert.Equal(t, before, a.Dec())
}

func TestSanityU256PathDeepCopySafe(t *testing.T) {
	parent := u256.NewUint(7)
	child := new(u256.Uint).Set(parent)
	child.Add(child, u256.NewUint(100))

	uassert.Equal(t, "7", parent.Dec())
	uassert.Equal(t, "107", child.Dec())
}

func TestSanityCoinsValueSemantics(t *testing.T) {
	a := chain.NewCoins(chain.NewCoin("ugnot", 100))
	beforeA := a.AmountOf("ugnot")

	mutate := func(c chain.Coins) chain.Coins {
		return c.Add(chain.NewCoins(chain.NewCoin("ugnot", 50)))
	}
	b := mutate(a)

	uassert.Equal(t, beforeA, a.AmountOf("ugnot"))
	uassert.Equal(t, int64(150), b.AmountOf("ugnot"))
	t.Logf("chain.Coins.Add: a=%d (unchanged), b=%d", a.AmountOf("ugnot"), b.AmountOf("ugnot"))
}

// chain.Coins is []Coin: passing it shares the slice header, so a child
// that indexes and assigns can leak across siblings. Verify parseCoins
// returns a fresh slice on each call.
func TestSanityCoinsSliceAliasing(t *testing.T) {
	a := parseCoins("100ugnot")
	b := parseCoins("100ugnot")
	uassert.Equal(t, int64(100), a.AmountOf("ugnot"))
	uassert.Equal(t, int64(100), b.AmountOf("ugnot"))

	if len(a) > 0 && len(b) > 0 {
		a[0].Amount = 999
		uassert.Equal(t, int64(100), b.AmountOf("ugnot"))
		t.Logf("parseCoins returns independent slices on each call")
	}
}
