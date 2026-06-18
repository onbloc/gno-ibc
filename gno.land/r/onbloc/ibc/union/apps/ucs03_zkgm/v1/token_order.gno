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
func (v *ucs03ZkgmV1) verifyTokenOrderV2(cur realm, channelId types.ChannelId, sender string, funds *funds, path *u256.Uint, order z.TokenOrderV2) error {
	if path == nil {
		path = u256.Zero()
	}
	switch order.Kind {
	case z.TOKEN_ORDER_KIND_INITIALIZE, z.TOKEN_ORDER_KIND_ESCROW:
		baseDenom := string(order.BaseToken)
		if err := v.rateLimit(cur, baseDenom, order.BaseAmount); err != nil {
			return err
		}

		if strings.HasPrefix(baseDenom, ibcDenomPrefix) {
			if err := v.burnVoucher(cur, baseDenom, sender, order.BaseAmount); err != nil {
				return err
			}
		} else if err := funds.sub(baseDenom, order.BaseAmount); err != nil {
			return err
		}

		v.increaseChannelBalanceV2(cur, channelId, path, order.BaseToken, order.QuoteToken, order.BaseAmount)
		return nil
	case z.TOKEN_ORDER_KIND_UNESCROW:
		baseDenom := string(order.BaseToken)
		if err := v.rateLimit(cur, baseDenom, order.BaseAmount); err != nil {
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
			return v.burnVoucher(cur, baseDenom, sender, order.BaseAmount)
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
func (v *ucs03ZkgmV1) executeTokenOrderV2(cur realm, packet types.Packet, relayer address, path *u256.Uint, order z.TokenOrderV2, intent bool) (types.RecvPacketResult, error) {
	if intent {
		return v.marketMakerFillV2(cur, relayer, order)
	}
	if path == nil {
		path = u256.Zero()
	}

	switch order.Kind {
	case z.TOKEN_ORDER_KIND_INITIALIZE:
		if len(order.Metadata) == 0 {
			return core.NewRecvPacketResult(types.PacketStatusUnknown, nil), errors.New("zkgm/v1: initialize requires metadata")
		}

		meta, err := z.DecodeTokenMetadata(order.Metadata)
		if err != nil {
			return core.NewRecvPacketResult(types.PacketStatusUnknown, nil), err
		}

		ti := z.DecodeTokenInitializerFromMetadata(meta)

		image := MetadataImage(meta)
		destChan, err := tokenOrderDestinationChannel(packet.DestinationChannelId)
		if err != nil {
			return core.NewRecvPacketResult(types.PacketStatusUnknown, nil), err
		}
		ibcDenom := PredictWrappedTokenV2(path, destChan, order.BaseToken, image)
		if string(order.QuoteToken) != ibcDenom || order.BaseAmount.Cmp(order.QuoteAmount) < 0 {
			return failureResult(cur, universalErrorAck()), nil
		}
		fee := new(u256.Uint).Sub(order.BaseAmount, order.QuoteAmount)
		if _, err := amountInt64(order.QuoteAmount); err != nil {
			return core.NewRecvPacketResult(types.PacketStatusUnknown, nil), err
		}
		if _, err := amountInt64(fee); err != nil {
			return core.NewRecvPacketResult(types.PacketStatusUnknown, nil), err
		}
		if ti.Decimals > grc20.MaxDecimals {
			return failureResult(cur, universalErrorAck()), nil
		}
		nextPath, err := z.UpdateChannelPath(path, destChan)
		if err != nil {
			return core.NewRecvPacketResult(types.PacketStatusUnknown, nil), err
		}
		if !order.QuoteAmount.IsZero() {
			if err := v.mintVoucher(cur, ibcDenom, image, ti.Name, ti.Symbol, ti.Decimals, string(order.Receiver), order.QuoteAmount); err != nil {
				return core.NewRecvPacketResult(types.PacketStatusUnknown, nil), err
			}
		}
		if !fee.IsZero() {
			if err := v.mintVoucher(cur, ibcDenom, image, ti.Name, ti.Symbol, ti.Decimals, string(relayer), fee); err != nil {
				panic(execFatal{err.Error()})
			}
		}
		v.store.SetTokenOrigin(0, cur, ibcDenom, nextPath)
	case z.TOKEN_ORDER_KIND_ESCROW:
		quoteDenom := string(order.QuoteToken)
		image, hasImage := v.store.GetMetadataImageOf(quoteDenom)
		destChan, err := tokenOrderDestinationChannel(packet.DestinationChannelId)
		if err != nil {
			return core.NewRecvPacketResult(types.PacketStatusUnknown, nil), err
		}
		predicted := ""
		if hasImage {
			predicted = PredictWrappedTokenV2(path, destChan, order.BaseToken, image)
		} else {
			image = [32]byte{}
			predicted = PredictWrappedTokenV1(path, destChan, order.BaseToken)
		}
		if quoteDenom != predicted || order.BaseAmount.Cmp(order.QuoteAmount) < 0 {
			return failureResult(cur, universalErrorAck()), nil
		}
		fee := new(u256.Uint).Sub(order.BaseAmount, order.QuoteAmount)
		if _, err := amountInt64(order.QuoteAmount); err != nil {
			return core.NewRecvPacketResult(types.PacketStatusUnknown, nil), err
		}
		if _, err := amountInt64(fee); err != nil {
			return core.NewRecvPacketResult(types.PacketStatusUnknown, nil), err
		}
		_, hasOrigin := v.store.GetTokenOrigin(quoteDenom)
		var nextPath *u256.Uint
		if !hasOrigin {
			nextPath, err = z.UpdateChannelPath(path, destChan)
			if err != nil {
				return core.NewRecvPacketResult(types.PacketStatusUnknown, nil), err
			}
		}
		if !order.QuoteAmount.IsZero() {
			if err := v.mintVoucher(cur, quoteDenom, image, "", "", 0, string(order.Receiver), order.QuoteAmount); err != nil {
				return core.NewRecvPacketResult(types.PacketStatusUnknown, nil), err
			}
		}
		if !fee.IsZero() {
			if err := v.mintVoucher(cur, quoteDenom, image, "", "", 0, string(relayer), fee); err != nil {
				panic(execFatal{err.Error()})
			}
		}
		if !hasOrigin {
			v.store.SetTokenOrigin(0, cur, quoteDenom, nextPath)
		}
	case z.TOKEN_ORDER_KIND_UNESCROW:
		reversedPath, err := z.ReverseChannelPath(path)
		if err != nil {
			return core.NewRecvPacketResult(types.PacketStatusUnknown, nil), err
		}
		if order.BaseAmount.Cmp(order.QuoteAmount) < 0 {
			return core.NewRecvPacketResult(types.PacketStatusUnknown, nil), errors.New("zkgm/v1: base amount below quote amount")
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
		if err := v.decreaseChannelBalanceV2(cur, packet.DestinationChannelId, reversedPath, order.QuoteToken, order.BaseToken, order.BaseAmount); err != nil {
			return core.NewRecvPacketResult(types.PacketStatusUnknown, nil), err
		}
		if !order.QuoteAmount.IsZero() {
			if err := v.sendNative(cur, string(order.QuoteToken), string(order.Receiver), order.QuoteAmount); err != nil {
				panic(execFatal{err.Error()})
			}
		}
		if !fee.IsZero() {
			if err := v.sendNative(cur, string(order.QuoteToken), string(relayer), fee); err != nil {
				panic(execFatal{err.Error()})
			}
		}
	case z.TOKEN_ORDER_KIND_SOLVE:
		return core.NewRecvPacketResult(types.PacketStatusUnknown, nil), errors.New("zkgm/v1: solve recv not implemented")
	default:
		return core.NewRecvPacketResult(types.PacketStatusUnknown, nil), errors.New("zkgm/v1: unknown token order kind")
	}

	ack, err := encodeTokenOrderSuccessAck(fillTypeProtocol(), nil)
	if err != nil {
		panic(execFatal{err.Error()})
	}

	return core.NewRecvPacketResult(types.PacketStatusSuccess, ack), nil
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
// Native maker funding is unsupported, so non-voucher quotes fall back to proven recv.
// marketMakerFillV2 fills a token order from the market maker's voucher balance, falling back to proven recv otherwise.
func (v *ucs03ZkgmV1) marketMakerFillV2(cur realm, relayer address, order z.TokenOrderV2) (types.RecvPacketResult, error) {
	quoteDenom := string(order.QuoteToken)
	if !v.store.HasVoucher(quoteDenom) {
		return core.NewRecvPacketResult(types.PacketStatusSuccess, cloneBytes(z.ACK_ERR_ONLY_MAKER)), nil
	}

	if _, err := amountInt64(order.QuoteAmount); err != nil {
		return core.NewRecvPacketResult(types.PacketStatusUnknown, nil), err
	}

	if err := v.transferVoucher(cur, quoteDenom, relayer, address(order.Receiver), order.QuoteAmount); err != nil {
		return core.NewRecvPacketResult(types.PacketStatusSuccess, cloneBytes(z.ACK_ERR_ONLY_MAKER)), nil
	}

	// The maker-funded voucher transfer is the quote-token assertion.
	ack, err := encodeTokenOrderSuccessAck(fillTypeMarketMaker(), []byte(relayer.String()))
	if err != nil {
		return core.NewRecvPacketResult(types.PacketStatusUnknown, nil), err
	}

	return core.NewRecvPacketResult(types.PacketStatusSuccess, ack), nil
}

// acknowledgeTokenOrderV2 settles the ack: refund on failure, or release escrow to the market maker on a maker fill.
// reference: https://github.com/unionlabs/union/blob/d91c5e94354e15801bd5f82dc658eae3b79f2dad/cosmwasm/app/ucs03-zkgm/src/contract.rs#L974-L1072
func (v *ucs03ZkgmV1) acknowledgeTokenOrderV2(cur realm, sourceChannelId types.ChannelId, path *u256.Uint, order z.TokenOrderV2, ack z.Ack) error {
	if ack.Tag.Eq(tagAckFailure()) {
		return v.refundV2(cur, sourceChannelId, path, order)
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
		return v.refundIBCVoucher(cur, order.BaseToken, marketMaker, order.BaseAmount)
	case z.TOKEN_ORDER_KIND_INITIALIZE, z.TOKEN_ORDER_KIND_ESCROW:
		return v.settleEscrowedV2(cur, sourceChannelId, path, order, marketMaker)
	default:
		return errors.New("zkgm/v1: unsupported token order kind for ack")
	}
}

// refundV2 returns a failed or timed-out token order's funds to the sender.
// reference: https://github.com/unionlabs/union/blob/d91c5e94354e15801bd5f82dc658eae3b79f2dad/cosmwasm/app/ucs03-zkgm/src/contract.rs#L918-L971
func (v *ucs03ZkgmV1) refundV2(cur realm, sourceChannelId types.ChannelId, path *u256.Uint, order z.TokenOrderV2) error {
	switch order.Kind {
	case z.TOKEN_ORDER_KIND_UNESCROW:
		return v.refundIBCVoucher(cur, order.BaseToken, string(order.Sender), order.BaseAmount)
	case z.TOKEN_ORDER_KIND_INITIALIZE, z.TOKEN_ORDER_KIND_ESCROW:
		return v.settleEscrowedV2(cur, sourceChannelId, path, order, string(order.Sender))
	default:
		return errors.New("zkgm/v1: unsupported token order kind for refund")
	}
}

// settleEscrowedV2 releases a previously escrowed INITIALIZE/ESCROW BaseAmount to
// recipient: it re-mints the voucher for `ibc/` denoms and releases native tokens
// from the proxy escrow otherwise. Shared by refundV2 and the market-maker fill
// branch of acknowledgeTokenOrderV2.
// settleEscrowedV2 releases a settled escrow to recipient: re-mint for ibc denoms, native release otherwise.
func (v *ucs03ZkgmV1) settleEscrowedV2(cur realm, sourceChannelId types.ChannelId, path *u256.Uint, order z.TokenOrderV2, recipient string) error {
	if _, err := amountInt64(order.BaseAmount); err != nil {
		return err
	}
	if err := v.decreaseChannelBalanceV2(cur, sourceChannelId, path, order.BaseToken, order.QuoteToken, order.BaseAmount); err != nil {
		return err
	}
	baseDenom := string(order.BaseToken)
	if strings.HasPrefix(baseDenom, ibcDenomPrefix) {
		return v.refundIBCVoucher(cur, order.BaseToken, recipient, order.BaseAmount)
	}
	return v.sendNative(cur, baseDenom, recipient, order.BaseAmount)
}

// refundIBCVoucher re-mints an IBC voucher to recipient, recovering the stored V2
// metadata image so the wrapped denom identity is preserved across ack/refund.
// refundIBCVoucher re-mints an IBC voucher to recipient, preserving the stored metadata image.
func (v *ucs03ZkgmV1) refundIBCVoucher(cur realm, baseToken []byte, recipient string, amount *u256.Uint) error {
	baseDenom := string(baseToken)
	image, _ := v.store.GetMetadataImageOf(baseDenom)
	return v.mintVoucher(cur, baseDenom, image, "", "", 0, recipient, amount)
}
