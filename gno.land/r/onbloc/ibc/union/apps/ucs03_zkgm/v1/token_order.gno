package impl

import (
	"errors"
	"strings"

	types "gno.land/p/onbloc/ibc/union/types"

	"gno.land/p/demo/tokens/grc20"
	u256 "gno.land/p/gnoswap/uint256"
	z "gno.land/p/onbloc/ibc/union/zkgm"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	core "gno.land/r/onbloc/ibc/union/core"
)

var errInvalidUnescrow = errors.New("zkgm/v1: invalid token order unescrow")

func tagAckSuccess() *u256.Uint       { return u256FromBytes32(z.TAG_ACK_SUCCESS) }
func tagAckFailure() *u256.Uint       { return u256FromBytes32(z.TAG_ACK_FAILURE) }
func fillTypeProtocol() *u256.Uint    { return u256FromBytes32(z.FILL_TYPE_PROTOCOL) }
func fillTypeMarketMaker() *u256.Uint { return u256FromBytes32(z.FILL_TYPE_MARKETMAKER) }

func (v *ZkgmV1) verifyTokenOrderV2(cur realm, channelId types.ChannelId, sender string, budget *sentCoinBudget, path *u256.Uint, order z.TokenOrderV2) error {
	if path == nil {
		path = u256.Zero()
	}
	switch order.Kind {
	case z.TOKEN_ORDER_KIND_INITIALIZE, z.TOKEN_ORDER_KIND_ESCROW:
		baseDenom := string(order.BaseToken)
		if err := zkgm.RateLimit(cross(cur), baseDenom, order.BaseAmount); err != nil {
			return err
		}

		if strings.HasPrefix(baseDenom, ibcDenomPrefix) {
			if err := zkgm.BurnVoucher(cross(cur), baseDenom, sender, order.BaseAmount); err != nil {
				return err
			}
		} else if err := budget.consume(baseDenom, order.BaseAmount); err != nil {
			return err
		}

		increaseChannelBalanceV2(cross(cur), channelId, path, order.BaseToken, order.QuoteToken, order.BaseAmount)
		return nil
	case z.TOKEN_ORDER_KIND_UNESCROW:
		baseDenom := string(order.BaseToken)
		if err := zkgm.RateLimit(cross(cur), baseDenom, order.BaseAmount); err != nil {
			return err
		}

		origin, ok := zkgm.GetTokenOrigin(baseDenom)
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
		image, ok := zkgm.GetMetadataImageOf(baseDenom)
		if !ok {
			image = [32]byte{}
		}
		wrappedV1 := PredictWrappedToken(intermediatePath, destChan, order.QuoteToken)
		wrappedV2 := PredictWrappedTokenV2(intermediatePath, destChan, order.QuoteToken, image)
		if baseDenom != wrappedV1 && baseDenom != wrappedV2 {
			return errInvalidUnescrow
		}
		if strings.HasPrefix(baseDenom, ibcDenomPrefix) {
			return zkgm.BurnVoucher(cross(cur), baseDenom, sender, order.BaseAmount)
		}
		return budget.consume(baseDenom, order.BaseAmount)
	case z.TOKEN_ORDER_KIND_SOLVE:
		return errors.New("zkgm/v1: solve token order not implemented")
	default:
		return errors.New("zkgm/v1: unknown token order kind")
	}
}

func (v *ZkgmV1) executeTokenOrderV2(cur realm, packet types.Packet, relayer address, path *u256.Uint, order z.TokenOrderV2, intent bool) (types.RecvPacketResult, error) {
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
			if err := zkgm.MintVoucher(cross(cur), ibcDenom, string(order.BaseToken), image, ti.Name, ti.Symbol, ti.Decimals, string(order.Receiver), order.QuoteAmount); err != nil {
				return core.NewRecvPacketResult(types.PacketStatusUnknown, nil), err
			}
		}
		if !fee.IsZero() {
			if err := zkgm.MintVoucher(cross(cur), ibcDenom, string(order.BaseToken), image, ti.Name, ti.Symbol, ti.Decimals, string(relayer), fee); err != nil {
				panic(execFatal{err.Error()})
			}
		}
		zkgm.SetTokenOrigin(cross(cur), ibcDenom, nextPath)
	case z.TOKEN_ORDER_KIND_ESCROW:
		quoteDenom := string(order.QuoteToken)
		image, hasImage := zkgm.GetMetadataImageOf(quoteDenom)
		destChan, err := tokenOrderDestinationChannel(packet.DestinationChannelId)
		if err != nil {
			return core.NewRecvPacketResult(types.PacketStatusUnknown, nil), err
		}
		predicted := ""
		if hasImage {
			predicted = PredictWrappedTokenV2(path, destChan, order.BaseToken, image)
		} else {
			image = [32]byte{}
			predicted = PredictWrappedToken(path, destChan, order.BaseToken)
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
		_, hasOrigin := zkgm.GetTokenOrigin(quoteDenom)
		var nextPath *u256.Uint
		if !hasOrigin {
			nextPath, err = z.UpdateChannelPath(path, destChan)
			if err != nil {
				return core.NewRecvPacketResult(types.PacketStatusUnknown, nil), err
			}
		}
		if !order.QuoteAmount.IsZero() {
			if err := zkgm.MintVoucher(cross(cur), quoteDenom, string(order.BaseToken), image, "", "", 0, string(order.Receiver), order.QuoteAmount); err != nil {
				return core.NewRecvPacketResult(types.PacketStatusUnknown, nil), err
			}
		}
		if !fee.IsZero() {
			if err := zkgm.MintVoucher(cross(cur), quoteDenom, string(order.BaseToken), image, "", "", 0, string(relayer), fee); err != nil {
				panic(execFatal{err.Error()})
			}
		}
		if !hasOrigin {
			zkgm.SetTokenOrigin(cross(cur), quoteDenom, nextPath)
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
		if err := decreaseChannelBalanceV2(cross(cur), packet.DestinationChannelId, reversedPath, order.QuoteToken, order.BaseToken, order.BaseAmount); err != nil {
			return core.NewRecvPacketResult(types.PacketStatusUnknown, nil), err
		}
		if !order.QuoteAmount.IsZero() {
			if err := sendNative(cur, string(order.QuoteToken), string(order.Receiver), order.QuoteAmount); err != nil {
				panic(execFatal{err.Error()})
			}
		}
		if !fee.IsZero() {
			if err := sendNative(cur, string(order.QuoteToken), string(relayer), fee); err != nil {
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
func (v *ZkgmV1) marketMakerFillV2(cur realm, relayer address, order z.TokenOrderV2) (types.RecvPacketResult, error) {
	quoteDenom := string(order.QuoteToken)
	if !zkgm.HasVoucher(quoteDenom) {
		return core.NewRecvPacketResult(types.PacketStatusSuccess, cloneBytes(z.ACK_ERR_ONLY_MAKER)), nil
	}

	if _, err := amountInt64(order.QuoteAmount); err != nil {
		return core.NewRecvPacketResult(types.PacketStatusUnknown, nil), err
	}

	if err := zkgm.TransferVoucher(cross(cur), quoteDenom, relayer, address(order.Receiver), order.QuoteAmount); err != nil {
		return core.NewRecvPacketResult(types.PacketStatusSuccess, cloneBytes(z.ACK_ERR_ONLY_MAKER)), nil
	}

	// The maker-funded voucher transfer is the quote-token assertion.
	ack, err := encodeTokenOrderSuccessAck(fillTypeMarketMaker(), []byte(relayer.String()))
	if err != nil {
		return core.NewRecvPacketResult(types.PacketStatusUnknown, nil), err
	}

	return core.NewRecvPacketResult(types.PacketStatusSuccess, ack), nil
}

func (v *ZkgmV1) acknowledgeTokenOrderV2(cur realm, sourceChannelId types.ChannelId, path *u256.Uint, order z.TokenOrderV2, ack z.Ack) error {
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
		return refundIBCVoucher(cur, order.BaseToken, marketMaker, order.BaseAmount)
	case z.TOKEN_ORDER_KIND_INITIALIZE, z.TOKEN_ORDER_KIND_ESCROW:
		return settleEscrowedV2(cur, sourceChannelId, path, order, marketMaker)
	default:
		return errors.New("zkgm/v1: unsupported token order kind for ack")
	}
}

func (v *ZkgmV1) refundV2(cur realm, sourceChannelId types.ChannelId, path *u256.Uint, order z.TokenOrderV2) error {
	switch order.Kind {
	case z.TOKEN_ORDER_KIND_UNESCROW:
		return refundIBCVoucher(cur, order.BaseToken, string(order.Sender), order.BaseAmount)
	case z.TOKEN_ORDER_KIND_INITIALIZE, z.TOKEN_ORDER_KIND_ESCROW:
		return settleEscrowedV2(cur, sourceChannelId, path, order, string(order.Sender))
	default:
		return errors.New("zkgm/v1: unsupported token order kind for refund")
	}
}

// settleEscrowedV2 releases a previously escrowed INITIALIZE/ESCROW BaseAmount
// to recipient. It re-mints the voucher for `ibc/` denoms and releases native
// tokens from the proxy escrow otherwise. It is shared by refundV2 and the
// market-maker fill branch of acknowledgeTokenOrderV2.
func settleEscrowedV2(cur realm, sourceChannelId types.ChannelId, path *u256.Uint, order z.TokenOrderV2, recipient string) error {
	if _, err := amountInt64(order.BaseAmount); err != nil {
		return err
	}
	if err := decreaseChannelBalanceV2(cross(cur), sourceChannelId, path, order.BaseToken, order.QuoteToken, order.BaseAmount); err != nil {
		return err
	}
	baseDenom := string(order.BaseToken)
	if strings.HasPrefix(baseDenom, ibcDenomPrefix) {
		return refundIBCVoucher(cur, order.BaseToken, recipient, order.BaseAmount)
	}
	return sendNative(cur, baseDenom, recipient, order.BaseAmount)
}

// refundIBCVoucher re-mints an IBC voucher to recipient, recovering the stored
// V2 metadata image so the wrapped denom identity is preserved across ack/refund
// flows.
func refundIBCVoucher(cur realm, baseToken []byte, recipient string, amount *u256.Uint) error {
	baseDenom := string(baseToken)
	image, _ := zkgm.GetMetadataImageOf(baseDenom)
	return zkgm.MintVoucher(cross(cur), baseDenom, baseDenom, image, "", "", 0, recipient, amount)
}

func sendNative(cur realm, denom string, receiver string, amount *u256.Uint) error {
	n, err := amountInt64(amount)
	if err != nil {
		return err
	}

	zkgm.ReleaseNative(cross(cur), denom, address(receiver), n)
	return nil
}
