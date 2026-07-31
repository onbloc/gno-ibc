package ucs03_zkgm

import (
	"testing"

	"gno.land/p/onbloc/ibc/union/types"

	"gno.land/p/nt/fqname/v0"
	"gno.land/p/nt/uassert/v0"
	z "gno.land/p/onbloc/ibc/union/zkgm"
	u256 "gno.land/p/onbloc/math/uint256"
	"gno.land/r/onbloc/ibc/union/core"
)

// Covers the first-sighting-deploy path: a forward-bound ESCROW order for a
// never-INITIALIZE'd token, resolved via TokenForwardMetadataResolver.

func mustTestTokenMetadata(t *testing.T, symbol string, decimals uint8) z.TokenMetadata {
	initBytes, err := z.EncodeTokenInitializer(z.TokenInitializer{
		Name:     "Test Token",
		Symbol:   symbol,
		Decimals: decimals,
	})
	uassert.NoError(t, err)

	return z.TokenMetadata{
		Implementation: []byte{0xAB, 0xCD},
		Initializer:    initBytes,
	}
}

func TestExecuteTokenOrderV2Forward_FirstSightingDeploy_Success(cur realm, t *testing.T) {
	testStore = newMockStore()
	ResetDeployForwardHandler(cross(cur))
	v := newTestImpl()

	path := u256.Zero()
	destChan := types.ChannelId(9)
	handlerAddr := testAddress("fwd-deploy")
	testStore.SetTokenForwardHandler(0, cur, mockDeployFwd, handlerAddr, forwardHandlerPkgPathForTest)

	baseToken := []byte("remote-native-asset")
	meta := mustTestTokenMetadata(t, "TTOK", 6)
	SetDeployResolveMetadata(cross(cur), meta)

	image := z.MetadataImage(meta)
	wrapped := z.PredictWrappedTokenV2(path, uint32(destChan), baseToken, image)

	// Deliberately do NOT pre-create the voucher: this is the first sighting.
	uassert.False(t, testStore.HasVoucher(wrapped))

	order := z.TokenOrderV2{
		Sender:      []byte("sender"),
		Receiver:    []byte(handlerAddr),
		BaseToken:   baseToken,
		BaseAmount:  u256.NewUint(21),
		QuoteToken:  []byte(wrapped),
		QuoteAmount: u256.NewUint(21),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
		Metadata:    []byte(`{"forward":{"receiver":"atone1receiver","channel":"07-tendermint-1"}}`),
	}
	packet := core.NewPacket(types.ChannelId(7), destChan, nil, 0)

	res, err := v.executeTokenOrderV2(0, cur, packet, address(testAddress("relayer")), nil, [32]byte{}, path, order, false)

	uassert.NoError(t, err)
	uassert.True(t, res.Status == types.PacketStatusAsync)
	uassert.Equal(t, 1, DeployForwardPrepareCalls(cross(cur)))
	uassert.Equal(t, 1, DeployForwardExecuteCalls(cross(cur)))
	uassert.True(t, testStore.HasVoucher(wrapped))
	uassert.Equal(t, int64(21), voucherBalanceOf(wrapped, handlerAddr))

	expectedBaseTokenKey := fqname.Construct(cur.PkgPath(), sanitizeVoucherSymbol("TTOK", wrapped))
	uassert.Equal(t, expectedBaseTokenKey, LastDeployForwardBaseTokenKey(cross(cur)))
	uassert.Equal(t, int64(21), LastDeployForwardAmount(cross(cur)))
}

func TestExecuteTokenOrderV2Forward_FirstSightingDeploy_ResolveError(cur realm, t *testing.T) {
	testStore = newMockStore()
	ResetDeployForwardHandler(cross(cur))
	v := newTestImpl()

	path := u256.Zero()
	destChan := types.ChannelId(9)
	handlerAddr := testAddress("fwd-deploy-err")
	testStore.SetTokenForwardHandler(0, cur, mockDeployFwd, handlerAddr, forwardHandlerPkgPathForTest)
	SetDeployResolveErr(cross(cur), "malformed memo")

	baseToken := []byte("remote-native-asset-err")
	// quoteToken doesn't matter: ResolveMetadata errors before it's ever compared.
	order := z.TokenOrderV2{
		Sender:      []byte("sender"),
		Receiver:    []byte(handlerAddr),
		BaseToken:   baseToken,
		BaseAmount:  u256.NewUint(21),
		QuoteToken:  []byte("ibc/does-not-matter"),
		QuoteAmount: u256.NewUint(21),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
		Metadata:    []byte(`not valid json`),
	}
	packet := core.NewPacket(types.ChannelId(7), destChan, nil, 0)

	_, err := v.executeTokenOrderV2(0, cur, packet, address(testAddress("relayer")), nil, [32]byte{}, path, order, false)

	uassert.Error(t, err)
	uassert.Equal(t, 0, DeployForwardPrepareCalls(cross(cur)))
}

func TestExecuteTokenOrderV2Forward_FirstSightingDeploy_NoMetadataStillRejects(cur realm, t *testing.T) {
	testStore = newMockStore()
	ResetDeployForwardHandler(cross(cur))
	v := newTestImpl()

	path := u256.Zero()
	destChan := types.ChannelId(9)
	handlerAddr := testAddress("fwd-deploy-nometa")
	testStore.SetTokenForwardHandler(0, cur, mockDeployFwd, handlerAddr, forwardHandlerPkgPathForTest)
	// resolveHasMeta stays false: resolver supported but memo has no metadata; must still reject.

	baseToken := []byte("remote-native-asset-nometa")
	wrapped := z.PredictWrappedToken(path, uint32(destChan), baseToken)

	order := z.TokenOrderV2{
		Sender:      []byte("sender"),
		Receiver:    []byte(handlerAddr),
		BaseToken:   baseToken,
		BaseAmount:  u256.NewUint(21),
		QuoteToken:  []byte(wrapped),
		QuoteAmount: u256.NewUint(21),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
		Metadata:    []byte(`{"forward":{"receiver":"atone1receiver","channel":"07-tendermint-1"}}`),
	}
	packet := core.NewPacket(types.ChannelId(7), destChan, nil, 0)

	res, err := v.executeTokenOrderV2(0, cur, packet, address(testAddress("relayer")), nil, [32]byte{}, path, order, false)

	uassert.NoError(t, err)
	uassert.True(t, res.Status == types.PacketStatusFailure)
	uassert.Equal(t, 0, DeployForwardPrepareCalls(cross(cur)))
	uassert.False(t, testStore.HasVoucher(wrapped))
}
