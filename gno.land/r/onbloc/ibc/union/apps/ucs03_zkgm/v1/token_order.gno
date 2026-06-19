package impl

import (
	"errors"
	"strings"

	types "gno.land/p/onbloc/ibc/union/types"

	"gno.land/p/demo/tokens/grc20"
	u256 "gno.land/p/gnoswap/uint256"
	z "gno.land/p/onbloc/ibc/union/zkgm"
	core "gno.land/r/onbloc/ibc/union/core"
)

var errInvalidUnescrow = errors.New("zkgm/v1: invalid token order unescrow")

// tagAckSuccess returns a fresh copy of the success ack tag.
func tagAckSuccess() *u256.Uint       { return u256FromBytes32(z.TAG_ACK_SUCCESS) }
func tagAckFailure() *u256.Uint       { return u256FromBytes32(z.TAG_ACK_FAILURE) }
func fillTypeProtocol() *u256.Uint    { return u256FromBytes32(z.FILL_TYPE_PROTOCOL) }
func fillTypeMarketMaker() *u256.Uint { return u256FromBytes32(z.FILL_TYPE_MARKETMAKER) }

// verifyTokenOrderV2 validates a token order on send: rate-limit, burn voucher or consume native funds, then escrow the channel balance.
// reference: https://github.com/unionlabs/union/blob/d91c5e94354e15801bd5f82dc658eae3b79f2dad/cosmwasm/app/ucs03-zkgm/src/contract.rs#L419-L547
func (v *ucs03ZkgmV1) verifyTokenOrderV2(_ int, rlm realm, channelId types.ChannelId, sender string, funds *funds, path *u256.Uint, order z.TokenOrderV2) error {
	if path == nil {
		path = u256.Zero()
	}
	switch order.Kind {
	case z.TOKEN_ORDER_KIND_INITIALIZE, z.TOKEN_ORDER_KIND_ESCROW:
		baseDenom := string(order.BaseToken)
		if err := v.rateLimit(0, rlm, baseDenom, order.BaseAmount); err != nil {
			return err
		}

		if strings.HasPrefix(baseDenom, ibcDenomPrefix) {
			if err := v.burnVoucher(0, rlm, baseDenom, sender, order.BaseAmount); err != nil {
				return err
			}
		} else if err := funds.sub(baseDenom, order.BaseAmount); err != nil {
			return err
		}

		v.increaseChannelBalanceV2(0, rlm, channelId, path, order.BaseToken, order.QuoteToken, order.BaseAmount)
		return nil
	case z.TOKEN_ORDER_KIND_UNESCROW:
		baseDenom := string(order.BaseToken)
		if err := v.rateLimit(0, rlm, baseDenom, order.BaseAmount); err != nil {
			return err
		}

		origin, ok := v.store.GetTokenOrigin(baseDenom)
		if !ok {
			return errInvalidUnescrow
		}
		intermediatePath, destChan := z.PopChannelFromPath(origin)
		reversed, err := z.ReverseChannelPath(intermediatePath)
		if err != nil {
			return err
		}
		if path.Cmp(reversed) != 0 {
			return errInvalidUnescrow
		}
		if channelId != types.ChannelId(destChan) {
			return errInvalidUnescrow
		}
		image, ok := v.store.GetMetadataImageOf(baseDenom)
		if !ok {
			image = [32]byte{}
		}
		wrappedV1 := PredictWrappedTokenV1(intermediatePath, destChan, order.QuoteToken)
		wrappedV2 := PredictWrappedTokenV2(intermediatePath, destChan, order.QuoteToken, image)
		if baseDenom != wrappedV1 && baseDenom != wrappedV2 {
			return errInvalidUnescrow
		}
		if strings.HasPrefix(baseDenom, ibcDenomPrefix) {
			return v.burnVoucher(0, rlm, baseDenom, sender, order.BaseAmount)
		}
		return funds.sub(baseDenom, order.BaseAmount)
	case z.TOKEN_ORDER_KIND_SOLVE:
		return errors.New("zkgm/v1: solve token order not implemented")
	default:
		return errors.New("zkgm/v1: unknown token order kind")
	}
}

// executeTokenOrderV2 settles a received token order: mint wrapped vouchers, release escrowed native, or fill from the market maker.
// reference: https://github.com/unionlabs/union/blob/d91c5e94354e15801bd5f82dc658eae3b79f2dad/cosmwasm/app/ucs03-zkgm/src/contract.rs#L2133-L2306
func (v *ucs03ZkgmV1) executeTokenOrderV2(_ int, rlm realm, packet types.Packet, relayer address, relayerMsg []byte, path *u256.Uint, order z.TokenOrderV2, intent bool) (types.RecvPacketResult, error) {
	// Intent packets and explicit solve orders are maker-only.
	if intent || order.Kind == z.TOKEN_ORDER_KIND_SOLVE {
		return v.marketMakerFillV2(0, rlm, relayer, relayerMsg, order)
	}
	if path == nil {
		path = u256.Zero()
	}

	quoteDenom := string(order.QuoteToken)
	baseCovers := order.BaseAmount.Cmp(order.QuoteAmount) >= 0

	// Direct unescrow path: an unwrap whose base covers the quote releases the
	// escrowed native asset to the receiver.
	if order.Kind == z.TOKEN_ORDER_KIND_UNESCROW && baseCovers {
		if err := v.rateLimit(0, rlm, quoteDenom, order.QuoteAmount); err != nil {
			return failureResult(universalErrorAck()), nil
		}
		return v.protocolFillUnescrowV2(0, rlm, packet, path, order, relayer)
	}

	destChan, err := tokenOrderDestinationChannel(packet.DestinationChannelId)
	if err != nil {
		return core.NewRecvPacketResult(types.PacketStatusUnknown, nil), err
	}

	// Predict the wrapped denom for an escrow/initialize order. A mismatch (or an
	// under-quote) is not an error: the order falls back to a market-maker fill.
	var (
		wrapped     string
		hasWrapped  bool
		image       [32]byte
		meta        z.TokenMetadata
		metaPresent bool
	)
	switch order.Kind {
	case z.TOKEN_ORDER_KIND_ESCROW:
		if img, ok := v.store.GetMetadataImageOf(quoteDenom); ok && !isZeroImage(img) {
			image = img
			wrapped = PredictWrappedTokenV2(path, destChan, order.BaseToken, image)
		} else {
			wrapped = PredictWrappedTokenV1(path, destChan, order.BaseToken)
		}
		hasWrapped = true
	case z.TOKEN_ORDER_KIND_INITIALIZE:
		// gno requires the metadata preimage to initialize a new wrapped token.
		if len(order.Metadata) == 0 {
			return failureResult(universalErrorAck()), nil
		}
		m, derr := z.DecodeTokenMetadata(order.Metadata)
		if derr != nil {
			return core.NewRecvPacketResult(types.PacketStatusUnknown, nil), derr
		}
		meta, metaPresent = m, true
		image = MetadataImage(meta)
		wrapped = PredictWrappedTokenV2(path, destChan, order.BaseToken, image)
		// A quote token that does not match the deterministic wrapped denom is an
		// invalid initialize order (union InvalidTokenOrderKind).
		if quoteDenom != wrapped {
			return failureResult(universalErrorAck()), nil
		}
		hasWrapped = true
	}

	// Protocol fill when the quote matches the predicted wrapped denom and the base
	// covers the quote; otherwise fall back to a market-maker fill.
	if hasWrapped && quoteDenom == wrapped && baseCovers {
		if err := v.rateLimit(0, rlm, quoteDenom, order.QuoteAmount); err != nil {
			return failureResult(universalErrorAck()), nil
		}
		canDeploy := order.Kind == z.TOKEN_ORDER_KIND_INITIALIZE
		return v.protocolFillMintV2(0, rlm, destChan, path, order, wrapped, image, meta, metaPresent, relayer, canDeploy)
	}

	return v.marketMakerFillV2(0, rlm, relayer, relayerMsg, order)
}

// protocolFillMintV2 mints the wrapped voucher for an escrow/initialize order:
// quote to the receiver, fee to the relayer, then records the token origin (and,
// for a deployable initialize, the foreign token). State is written only after the
// mint succeeds so a recovered failure cannot leave orphan origin state.
// reference: https://github.com/unionlabs/union/blob/d91c5e94354e15801bd5f82dc658eae3b79f2dad/cosmwasm/app/ucs03-zkgm/src/contract.rs#L2309-L2413
func (v *ucs03ZkgmV1) protocolFillMintV2(_ int, rlm realm, destChan uint32, path *u256.Uint, order z.TokenOrderV2, wrappedDenom string, image [32]byte, meta z.TokenMetadata, metaPresent bool, relayer address, canDeploy bool) (types.RecvPacketResult, error) {
	fee := new(u256.Uint).Sub(order.BaseAmount, order.QuoteAmount)
	if _, err := amountInt64(order.QuoteAmount); err != nil {
		return core.NewRecvPacketResult(types.PacketStatusUnknown, nil), err
	}
	if _, err := amountInt64(fee); err != nil {
		return core.NewRecvPacketResult(types.PacketStatusUnknown, nil), err
	}

	// A deployable initialize carries the token metadata (name/symbol/decimals);
	// reject out-of-range decimals before any mint.
	name, symbol := "", ""
	var decimals uint8
	if canDeploy && metaPresent {
		ti := z.DecodeTokenInitializerFromMetadata(meta)
		if ti.Decimals > grc20.MaxDecimals {
			return failureResult(universalErrorAck()), nil
		}
		name, symbol, decimals = ti.Name, ti.Symbol, ti.Decimals
	}

	// Compute the origin update before minting so a path error fails closed
	// pre-mutation.
	_, hasOrigin := v.store.GetTokenOrigin(wrappedDenom)
	var nextPath *u256.Uint
	if !hasOrigin {
		np, err := z.UpdateChannelPath(path, destChan)
		if err != nil {
			return core.NewRecvPacketResult(types.PacketStatusUnknown, nil), err
		}
		nextPath = np
	}

	if !order.QuoteAmount.IsZero() {
		if err := v.mintVoucher(0, rlm, wrappedDenom, image, name, symbol, decimals, string(order.Receiver), order.QuoteAmount); err != nil {
			return core.NewRecvPacketResult(types.PacketStatusUnknown, nil), err
		}
	}
	if !fee.IsZero() {
		if err := v.mintVoucher(0, rlm, wrappedDenom, image, name, symbol, decimals, string(relayer), fee); err != nil {
			panic(execFatal{err.Error()})
		}
	}

	if !hasOrigin {
		v.store.SetTokenOrigin(0, rlm, wrappedDenom, nextPath)
		if canDeploy {
			v.store.SetForeignToken(0, rlm, wrappedDenom, order.BaseToken)
		}
	}

	ack, err := encodeTokenOrderSuccessAck(fillTypeProtocol(), nil)
	if err != nil {
		panic(execFatal{err.Error()})
	}
	return core.NewRecvPacketResult(types.PacketStatusSuccess, ack), nil
}

// protocolFillUnescrowV2 releases an escrowed native asset for an unwrap order:
// decrease the channel balance, then send the quote to the receiver and the fee to
// the relayer from the proxy escrow.
// reference: https://github.com/unionlabs/union/blob/d91c5e94354e15801bd5f82dc658eae3b79f2dad/cosmwasm/app/ucs03-zkgm/src/contract.rs#L2415-L2488
func (v *ucs03ZkgmV1) protocolFillUnescrowV2(_ int, rlm realm, packet types.Packet, path *u256.Uint, order z.TokenOrderV2, relayer address) (types.RecvPacketResult, error) {
	reversedPath, err := z.ReverseChannelPath(path)
	if err != nil {
		return core.NewRecvPacketResult(types.PacketStatusUnknown, nil), err
	}
	fee := new(u256.Uint).Sub(order.BaseAmount, order.QuoteAmount)
	if _, err := amountInt64(order.BaseAmount); err != nil {
		return core.NewRecvPacketResult(types.PacketStatusUnknown, nil), err
	}
	if _, err := amountInt64(order.QuoteAmount); err != nil {
		return core.NewRecvPacketResult(types.PacketStatusUnknown, nil), err
	}
	if _, err := amountInt64(fee); err != nil {
		return core.NewRecvPacketResult(types.PacketStatusUnknown, nil), err
	}
	if err := v.decreaseChannelBalanceV2(0, rlm, packet.DestinationChannelId, reversedPath, order.QuoteToken, order.BaseToken, order.BaseAmount); err != nil {
		return core.NewRecvPacketResult(types.PacketStatusUnknown, nil), err
	}
	if !order.QuoteAmount.IsZero() {
		if err := v.sendNative(0, rlm, string(order.QuoteToken), string(order.Receiver), order.QuoteAmount); err != nil {
			panic(execFatal{err.Error()})
		}
	}
	if !fee.IsZero() {
		if err := v.sendNative(0, rlm, string(order.QuoteToken), string(relayer), fee); err != nil {
			panic(execFatal{err.Error()})
		}
	}

	ack, err := encodeTokenOrderSuccessAck(fillTypeProtocol(), nil)
	if err != nil {
		panic(execFatal{err.Error()})
	}
	return core.NewRecvPacketResult(types.PacketStatusSuccess, ack), nil
}

// isZeroImage reports whether a metadata image is the zero value, selecting the V1
// wrapped-token prediction when true.
func isZeroImage(image [32]byte) bool {
	return image == [32]byte{}
}

// encodeTokenOrderSuccessAck builds a success token-order ack with the given fill type.
func encodeTokenOrderSuccessAck(fillType *u256.Uint, marketMaker []byte) ([]byte, error) {
	innerAck, err := z.EncodeTokenOrderAck(z.TokenOrderAck{
		FillType:    fillType,
		MarketMaker: marketMaker,
	})
	if err != nil {
		return nil, err
	}
	return z.EncodeAck(z.Ack{Tag: tagAckSuccess(), InnerAck: innerAck})
}

// marketMakerFillV2 fills a token order from the market maker's voucher balance.
// Native maker funding is unsupported, so non-voucher quotes fall back to proven
// recv (ACK_ERR_ONLY_MAKER). The success ack carries the relayer-supplied
// market_maker settlement target (relayer_msg), defaulting to the relayer address.
func (v *ucs03ZkgmV1) marketMakerFillV2(_ int, rlm realm, relayer address, relayerMsg []byte, order z.TokenOrderV2) (types.RecvPacketResult, error) {
	quoteDenom := string(order.QuoteToken)
	if !v.store.HasVoucher(quoteDenom) {
		return core.NewRecvPacketResult(types.PacketStatusSuccess, cloneBytes(z.ACK_ERR_ONLY_MAKER)), nil
	}

	if _, err := amountInt64(order.QuoteAmount); err != nil {
		return core.NewRecvPacketResult(types.PacketStatusUnknown, nil), err
	}

	if err := v.transferVoucher(0, rlm, quoteDenom, relayer, address(order.Receiver), order.QuoteAmount); err != nil {
		return core.NewRecvPacketResult(types.PacketStatusSuccess, cloneBytes(z.ACK_ERR_ONLY_MAKER)), nil
	}

	// market_maker is the relayer-supplied settlement target (union saves
	// relayer_msg into MARKET_MAKER); fall back to the relayer's own address when
	// no message was attached.
	marketMaker := relayerMsg
	if len(marketMaker) == 0 {
		marketMaker = []byte(relayer.String())
	}
	ack, err := encodeTokenOrderSuccessAck(fillTypeMarketMaker(), marketMaker)
	if err != nil {
		return core.NewRecvPacketResult(types.PacketStatusUnknown, nil), err
	}

	return core.NewRecvPacketResult(types.PacketStatusSuccess, ack), nil
}

// acknowledgeTokenOrderV2 settles the ack: refund on failure, or release escrow to the market maker on a maker fill.
// reference: https://github.com/unionlabs/union/blob/d91c5e94354e15801bd5f82dc658eae3b79f2dad/cosmwasm/app/ucs03-zkgm/src/contract.rs#L974-L1072
func (v *ucs03ZkgmV1) acknowledgeTokenOrderV2(_ int, rlm realm, sourceChannelId types.ChannelId, path *u256.Uint, order z.TokenOrderV2, ack z.Ack) error {
	if ack.Tag.Eq(tagAckFailure()) {
		return v.refundV2(0, rlm, sourceChannelId, path, order)
	}
	if !ack.Tag.Eq(tagAckSuccess()) {
		return errors.New("zkgm/v1: unknown ack tag")
	}
	orderAck, err := z.DecodeTokenOrderAck(ack.InnerAck)
	if err != nil {
		return err
	}
	if orderAck.FillType.Eq(fillTypeProtocol()) {
		return nil
	}
	if !orderAck.FillType.Eq(fillTypeMarketMaker()) {
		return errors.New("zkgm/v1: unknown fill type")
	}

	marketMaker := string(orderAck.MarketMaker)
	switch order.Kind {
	case z.TOKEN_ORDER_KIND_UNESCROW:
		return v.refundIBCVoucher(0, rlm, order.BaseToken, marketMaker, order.BaseAmount)
	case z.TOKEN_ORDER_KIND_INITIALIZE, z.TOKEN_ORDER_KIND_ESCROW:
		return v.settleEscrowedV2(0, rlm, sourceChannelId, path, order, marketMaker)
	default:
		return errors.New("zkgm/v1: unsupported token order kind for ack")
	}
}

// refundV2 returns a failed or timed-out token order's funds to the sender.
// reference: https://github.com/unionlabs/union/blob/d91c5e94354e15801bd5f82dc658eae3b79f2dad/cosmwasm/app/ucs03-zkgm/src/contract.rs#L918-L971
func (v *ucs03ZkgmV1) refundV2(_ int, rlm realm, sourceChannelId types.ChannelId, path *u256.Uint, order z.TokenOrderV2) error {
	switch order.Kind {
	case z.TOKEN_ORDER_KIND_UNESCROW:
		return v.refundIBCVoucher(0, rlm, order.BaseToken, string(order.Sender), order.BaseAmount)
	case z.TOKEN_ORDER_KIND_INITIALIZE, z.TOKEN_ORDER_KIND_ESCROW:
		return v.settleEscrowedV2(0, rlm, sourceChannelId, path, order, string(order.Sender))
	default:
		return errors.New("zkgm/v1: unsupported token order kind for refund")
	}
}

// settleEscrowedV2 releases a previously escrowed INITIALIZE/ESCROW BaseAmount to
// recipient: it re-mints the voucher for `ibc/` denoms and releases native tokens
// from the proxy escrow otherwise. Shared by refundV2 and the market-maker fill
// branch of acknowledgeTokenOrderV2.
// settleEscrowedV2 releases a settled escrow to recipient: re-mint for ibc denoms, native release otherwise.
func (v *ucs03ZkgmV1) settleEscrowedV2(_ int, rlm realm, sourceChannelId types.ChannelId, path *u256.Uint, order z.TokenOrderV2, recipient string) error {
	if _, err := amountInt64(order.BaseAmount); err != nil {
		return err
	}
	if err := v.decreaseChannelBalanceV2(0, rlm, sourceChannelId, path, order.BaseToken, order.QuoteToken, order.BaseAmount); err != nil {
		return err
	}
	baseDenom := string(order.BaseToken)
	if strings.HasPrefix(baseDenom, ibcDenomPrefix) {
		return v.refundIBCVoucher(0, rlm, order.BaseToken, recipient, order.BaseAmount)
	}
	return v.sendNative(0, rlm, baseDenom, recipient, order.BaseAmount)
}

// refundIBCVoucher re-mints an IBC voucher to recipient, recovering the stored V2
// metadata image so the wrapped denom identity is preserved across ack/refund.
// refundIBCVoucher re-mints an IBC voucher to recipient, preserving the stored metadata image.
func (v *ucs03ZkgmV1) refundIBCVoucher(_ int, rlm realm, baseToken []byte, recipient string, amount *u256.Uint) error {
	baseDenom := string(baseToken)
	image, _ := v.store.GetMetadataImageOf(baseDenom)
	return v.mintVoucher(0, rlm, baseDenom, image, "", "", 0, recipient, amount)
}
