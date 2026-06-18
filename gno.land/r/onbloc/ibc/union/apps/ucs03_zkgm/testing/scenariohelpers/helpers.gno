package scenariohelpers

import (
	types "gno.land/p/onbloc/ibc/union/types"

	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/testutils/v0"
	z "gno.land/p/onbloc/ibc/union/zkgm"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	e2e "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/e2e"
	impl "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	core "gno.land/r/onbloc/ibc/union/core"
)

const (
	ScenarioImplPath = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
)

func NewV1Harness(cur realm) zkgm.ZkgmImpl {
	return impl.New(cross(cur))
}

func RegisterV1(cur realm) {
	impl.Register(cross(cur))
}

func InstallV1Harness(cur realm) zkgm.ZkgmImpl {
	inst := NewV1Harness(cross(cur))
	RegisterV1(cross(cur))
	return inst
}

func DecodeTokenMetadata(bz []byte) z.TokenMetadata {
	meta, err := z.DecodeTokenMetadata(bz)
	if err != nil {
		panic(err)
	}
	return meta
}

func TokenOrderPacketData(cur realm, order z.TokenOrderV2) []byte {
	return e2e.MustPacketData(cross(cur), e2e.MustTokenOrderInstruction(cross(cur), order))
}

func ChannelBalanceStr(channelId types.ChannelId, path *u256.Uint, baseToken []byte, quoteToken []byte) string {
	balance := zkgm.GetChannelBalanceV2(impl.ChannelBalanceKeyV2(channelId, path, baseToken, quoteToken))
	if balance == nil {
		return "0"
	}
	return balance.ToString()
}

func MintVoucher(cur realm, inst zkgm.ZkgmImpl, channelId types.ChannelId, base string, receiver string, amount uint64, symbol string) string {
	meta := e2e.MustTokenMetadata(cross(cur), "grc20", z.TokenInitializer{Name: base, Symbol: symbol, Decimals: 6})
	quoteToken := impl.PredictWrappedTokenV2(u256.Zero(), uint32(channelId), []byte(base), impl.MetadataImage(DecodeTokenMetadata(meta)))
	order := z.TokenOrderV2{
		Sender:      []byte("remote"),
		Receiver:    []byte(receiver),
		BaseToken:   []byte(base),
		BaseAmount:  u256.NewUint(amount),
		QuoteToken:  []byte(quoteToken),
		QuoteAmount: u256.NewUint(amount),
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
		Metadata:    meta,
	}
	packet := core.NewPacket(types.ChannelId(1), channelId, TokenOrderPacketData(cross(cur), order), types.Timestamp(100))
	inst.Recv(cross(cur), packet, testutils.TestAddress("scenario-relayer"), nil)
	return quoteToken
}
