// PKGPATH: gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/e2e/scenarios_direct
package scenarios_direct

import (
	stdtesting "testing"

	types "gno.land/p/onbloc/ibc/union/types"

	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/testutils/v0"
	z "gno.land/p/onbloc/ibc/union/zkgm"
	tb "gno.land/p/onbloc/ibc/union/zkgm/tokenbucket"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	e2e "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/e2e"
	sh "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/scenariohelpers"
	impl "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	core "gno.land/r/onbloc/ibc/union/core"
)

func main(cur realm) {
	inst := sh.InstallV1Harness(cross(cur))
	receiver := string(testutils.TestAddress("zs88-receiver"))
	baseToken := "rate-limited-base"
	channelId := types.ChannelId(88)

	bucket, err := tb.New(u256.NewUint(1), u256.NewUint(1), u256.NewUint(1))
	if err != nil {
		panic(err)
	}
	stdtesting.SetRealm(stdtesting.NewCodeRealm(zkgm.ProductionImplPath()))
	zkgm.SetTokenBucket(cross(cur), baseToken, bucket)
	stdtesting.SetRealm(stdtesting.NewCodeRealm("gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/e2e/scenarios_direct"))

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
	packet := core.NewPacket(types.ChannelId(1), channelId, sh.TokenOrderPacketData(cross(cur), order), types.Timestamp(100))

	println("[SCENARIO] recv mint is not charged against send-side bucket")
	res := inst.Recv(cross(cur), packet, testutils.TestAddress("zs88-relayer"), nil)
	println("recv_status", int(res.Status))
	println("receiver_balance", impl.VoucherBalanceOf(quoteToken, address(receiver)))
}

// Output:
// [SCENARIO] recv mint is not charged against send-side bucket
// recv_status 1
// receiver_balance 25
