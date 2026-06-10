// PKGPATH: gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/loader
package loader

import (
	u256 "gno.land/p/gnoswap/uint256"
	tb "gno.land/p/onbloc/tokenbucket"
	"gno.land/p/nt/testutils/v0"
	z "gno.land/p/onbloc/unionibc/zkgm"
	zkgm "gno.land/r/onbloc/unionibc/v1/apps/zkgm"
	e2e "gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/e2e"
	sh "gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/scenariohelpers"
	impl "gno.land/r/onbloc/unionibc/v1/apps/zkgm/v0/impl"
	core "gno.land/r/onbloc/unionibc/v1/core"
)

func main(cur realm) {
	inst := sh.InstallImpl(cross(cur))
	receiver := string(testutils.TestAddress("zs88-receiver"))
	baseToken := "rate-limited-base"
	channelId := core.ChannelId(88)

	bucket, err := tb.New(u256.NewUint(1), u256.NewUint(1), u256.NewUint(1))
	if err != nil {
		panic(err)
	}
	zkgm.SetTokenBucket(cross(cur), baseToken, bucket)

	metaBytes := e2e.MustTokenMetadata(cross(cur), "grc20", z.TokenInitializer{Name: "Rate Limited", Symbol: "RL", Decimals: 6})
	quoteToken := impl.PredictWrappedTokenV2(u256.Zero(), uint32(channelId), []byte(baseToken), impl.MetadataImage(sh.DecodeTokenMetadata(metaBytes)))
	order := z.TokenOrderV2{
		Sender:      []byte("remote"),
		Receiver:    []byte(receiver),
		BaseToken:   []byte(baseToken),
		BaseAmount:  u256.NewUint(25),
		QuoteToken:  []byte(quoteToken),
		QuoteAmount: u256.NewUint(25),
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
		Metadata:    metaBytes,
	}
	packet := core.NewPacket(cross(cur), core.ChannelId(1), channelId, sh.TokenOrderPacketData(cross(cur), order), 0, core.Timestamp(100))

	println("[SCENARIO] recv mint is not charged against send-side bucket")
	res := inst.Recv(cross(cur), packet, testutils.TestAddress("zs88-relayer"), nil)
	println("recv_status", int(res.Status))
	println("receiver_balance", impl.VoucherBalanceOf(quoteToken, address(receiver)))
}

// Output:
// [SCENARIO] recv mint is not charged against send-side bucket
// recv_status 1
// receiver_balance 25
