package impl

import (
	"chain"
	"chain/banker"
	"chain/runtime"
	"errors"
	"strings"

	z "gno.land/p/gnoswap/ibc/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
	core "gno.land/r/core/ibc/v1/core"
	zkgm "gno.land/r/gnoswap/ibc/v1/apps/zkgm"
)

var (
	tagAckSuccess       = u256FromBytes32(z.TAG_ACK_SUCCESS)
	tagAckFailure       = u256FromBytes32(z.TAG_ACK_FAILURE)
	fillTypeProtocol    = u256FromBytes32(z.FILL_TYPE_PROTOCOL)
	fillTypeMarketMaker = u256FromBytes32(z.FILL_TYPE_MARKETMAKER)
	errInvalidUnescrow  = errors.New("zkgm/v1: invalid token order unescrow")
)

func (v *ZkgmV1) verifyTokenOrderV2(channelId core.ChannelId, sender string, sent chain.Coins, path *u256.Uint, order z.TokenOrderV2) error {
	if path == nil {
		path = u256.Zero()
	}
	switch order.Kind {
	case z.TOKEN_ORDER_KIND_INITIALIZE, z.TOKEN_ORDER_KIND_ESCROW:
		baseDenom := string(order.BaseToken)
		if err := zkgm.RateLimit(cross, baseDenom, order.BaseAmount); err != nil {
			return err
		}

		if strings.HasPrefix(baseDenom, ibcDenomPrefix) {
			if err := burnVoucher(cross, baseDenom, sender, order.BaseAmount); err != nil {
				return err
			}
		} else if err := requireSentCoin(sent, baseDenom, order.BaseAmount); err != nil {
			return err
		}

		increaseChannelBalanceV2(cross, channelId, path, order.BaseToken, order.QuoteToken, order.BaseAmount)
		return nil
	case z.TOKEN_ORDER_KIND_UNESCROW:
		baseDenom := string(order.BaseToken)
		if err := zkgm.RateLimit(cross, baseDenom, order.BaseAmount); err != nil {
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
		if channelId != core.ChannelId(destChan) {
			return errInvalidUnescrow
		}
		image, ok := zkgm.GetMetadataImageOf(baseDenom)
		if !ok {
			image = [32]byte{}
		}
		wrappedV1 := PredictWrappedTokenV1(intermediatePath, destChan, order.QuoteToken)
		wrappedV2 := PredictWrappedTokenV2(intermediatePath, destChan, order.QuoteToken, image)
		if baseDenom != wrappedV1 && baseDenom != wrappedV2 {
			return errInvalidUnescrow
		}
		if strings.HasPrefix(baseDenom, ibcDenomPrefix) {
			return burnVoucher(cross, baseDenom, sender, order.BaseAmount)
		}
		return requireSentCoin(sent, baseDenom, order.BaseAmount)
	case z.TOKEN_ORDER_KIND_SOLVE:
		return errors.New("zkgm/v1: solve token order not implemented")
	default:
		return errors.New("zkgm/v1: unknown token order kind")
	}
}

func (v *ZkgmV1) executeTokenOrderV2(packet core.Packet, relayer address, path *u256.Uint, order z.TokenOrderV2) (core.RecvPacketResult, error) {
	if path == nil {
		path = u256.Zero()
	}
	switch order.Kind {
	case z.TOKEN_ORDER_KIND_INITIALIZE:
		if len(order.Metadata) == 0 {
			return core.RecvPacketResult{}, errors.New("zkgm/v1: initialize requires metadata")
		}

		meta, err := z.DecodeTokenMetadata(order.Metadata)
		if err != nil {
			return core.RecvPacketResult{}, err
		}

		image := MetadataImage(meta)
		destChan, err := tokenOrderDestinationChannel(packet.DestinationChannelId)
		if err != nil {
			return core.RecvPacketResult{}, err
		}
		ibcDenom := PredictWrappedTokenV2(path, destChan, order.BaseToken, image)
		if string(order.QuoteToken) != ibcDenom || order.BaseAmount.Cmp(order.QuoteAmount) < 0 {
			return failureResult(universalErrorAck()), nil
		}
		fee := new(u256.Uint).Sub(order.BaseAmount, order.QuoteAmount)
		if _, err := amountInt64(order.QuoteAmount); err != nil {
			return core.RecvPacketResult{}, err
		}
		if _, err := amountInt64(fee); err != nil {
			return core.RecvPacketResult{}, err
		}
		nextPath, err := z.UpdateChannelPath(path, destChan)
		if err != nil {
			return core.RecvPacketResult{}, err
		}
		if !order.QuoteAmount.IsZero() {
			if err := mintVoucher(cross, ibcDenom, string(order.BaseToken), image, string(order.Receiver), order.QuoteAmount); err != nil {
				return core.RecvPacketResult{}, err
			}
		}
		if !fee.IsZero() {
			if err := mintVoucher(cross, ibcDenom, string(order.BaseToken), image, string(relayer), fee); err != nil {
				return core.RecvPacketResult{}, err
			}
		}
		zkgm.SetTokenOrigin(cross, ibcDenom, nextPath)
	case z.TOKEN_ORDER_KIND_ESCROW:
		quoteDenom := string(order.QuoteToken)
		image, hasImage := zkgm.GetMetadataImageOf(quoteDenom)
		destChan, err := tokenOrderDestinationChannel(packet.DestinationChannelId)
		if err != nil {
			return core.RecvPacketResult{}, err
		}
		predicted := ""
		if hasImage {
			predicted = PredictWrappedTokenV2(path, destChan, order.BaseToken, image)
		} else {
			image = [32]byte{}
			predicted = PredictWrappedTokenV1(path, destChan, order.BaseToken)
		}
		if quoteDenom != predicted || order.BaseAmount.Cmp(order.QuoteAmount) < 0 {
			return failureResult(universalErrorAck()), nil
		}
		fee := new(u256.Uint).Sub(order.BaseAmount, order.QuoteAmount)
		if _, err := amountInt64(order.QuoteAmount); err != nil {
			return core.RecvPacketResult{}, err
		}
		if _, err := amountInt64(fee); err != nil {
			return core.RecvPacketResult{}, err
		}
		_, hasOrigin := zkgm.GetTokenOrigin(quoteDenom)
		var nextPath *u256.Uint
		if !hasOrigin {
			nextPath, err = z.UpdateChannelPath(path, destChan)
			if err != nil {
				return core.RecvPacketResult{}, err
			}
		}
		if !order.QuoteAmount.IsZero() {
			if err := mintVoucher(cross, quoteDenom, string(order.BaseToken), image, string(order.Receiver), order.QuoteAmount); err != nil {
				return core.RecvPacketResult{}, err
			}
		}
		if !fee.IsZero() {
			if err := mintVoucher(cross, quoteDenom, string(order.BaseToken), image, string(relayer), fee); err != nil {
				return core.RecvPacketResult{}, err
			}
		}
		if !hasOrigin {
			zkgm.SetTokenOrigin(cross, quoteDenom, nextPath)
		}
	case z.TOKEN_ORDER_KIND_UNESCROW:
		reversedPath, err := z.ReverseChannelPath(path)
		if err != nil {
			return core.RecvPacketResult{}, err
		}
		if order.BaseAmount.Cmp(order.QuoteAmount) < 0 {
			return core.RecvPacketResult{}, errors.New("zkgm/v1: base amount below quote amount")
		}
		fee := new(u256.Uint).Sub(order.BaseAmount, order.QuoteAmount)
		if _, err := amountInt64(order.BaseAmount); err != nil {
			return core.RecvPacketResult{}, err
		}
		if _, err := amountInt64(order.QuoteAmount); err != nil {
			return core.RecvPacketResult{}, err
		}
		if _, err := amountInt64(fee); err != nil {
			return core.RecvPacketResult{}, err
		}
		if err := decreaseChannelBalanceV2(cross, packet.DestinationChannelId, reversedPath, order.QuoteToken, order.BaseToken, order.BaseAmount); err != nil {
			return core.RecvPacketResult{}, err
		}
		if !order.QuoteAmount.IsZero() {
			if err := sendNative(string(order.QuoteToken), string(order.Receiver), order.QuoteAmount); err != nil {
				return core.RecvPacketResult{}, err
			}
		}
		if !fee.IsZero() {
			if err := sendNative(string(order.QuoteToken), string(relayer), fee); err != nil {
				return core.RecvPacketResult{}, err
			}
		}
	case z.TOKEN_ORDER_KIND_SOLVE:
		return core.RecvPacketResult{}, errors.New("zkgm/v1: solve recv not implemented")
	default:
		return core.RecvPacketResult{}, errors.New("zkgm/v1: unknown token order kind")
	}

	innerAck, err := z.EncodeTokenOrderAck(z.TokenOrderAck{
		FillType:    fillTypeProtocol,
		MarketMaker: nil,
	})
	if err != nil {
		return core.RecvPacketResult{}, err
	}

	ack, err := z.EncodeAck(z.Ack{Tag: tagAckSuccess, InnerAck: innerAck})
	if err != nil {
		return core.RecvPacketResult{}, err
	}

	return core.RecvPacketResult{Status: core.PacketStatusSuccess, Ack: ack}, nil
}

func (v *ZkgmV1) acknowledgeTokenOrderV2(sourceChannelId core.ChannelId, path *u256.Uint, order z.TokenOrderV2, ack z.Ack) error {
	if ack.Tag.Eq(tagAckFailure) {
		return v.refundV2(sourceChannelId, path, order)
	}
	if !ack.Tag.Eq(tagAckSuccess) {
		return errors.New("zkgm/v1: unknown ack tag")
	}
	orderAck, err := z.DecodeTokenOrderAck(ack.InnerAck)
	if err != nil {
		return err
	}
	if orderAck.FillType.Eq(fillTypeProtocol) {
		return nil
	}
	if !orderAck.FillType.Eq(fillTypeMarketMaker) {
		return errors.New("zkgm/v1: unknown fill type")
	}

	marketMaker := string(orderAck.MarketMaker)
	switch order.Kind {
	case z.TOKEN_ORDER_KIND_UNESCROW:
		return refundIBCVoucher(order.BaseToken, marketMaker, order.BaseAmount)
	case z.TOKEN_ORDER_KIND_INITIALIZE, z.TOKEN_ORDER_KIND_ESCROW:
		if _, err := amountInt64(order.BaseAmount); err != nil {
			return err
		}
		if err := decreaseChannelBalanceV2(cross, sourceChannelId, path, order.BaseToken, order.QuoteToken, order.BaseAmount); err != nil {
			return err
		}
		return sendNative(string(order.BaseToken), marketMaker, order.BaseAmount)
	default:
		return errors.New("zkgm/v1: unsupported token order kind for ack")
	}
}

func (v *ZkgmV1) refundV2(sourceChannelId core.ChannelId, path *u256.Uint, order z.TokenOrderV2) error {
	switch order.Kind {
	case z.TOKEN_ORDER_KIND_UNESCROW:
		return refundIBCVoucher(order.BaseToken, string(order.Sender), order.BaseAmount)
	case z.TOKEN_ORDER_KIND_INITIALIZE, z.TOKEN_ORDER_KIND_ESCROW:
		if _, err := amountInt64(order.BaseAmount); err != nil {
			return err
		}
		if err := decreaseChannelBalanceV2(cross, sourceChannelId, path, order.BaseToken, order.QuoteToken, order.BaseAmount); err != nil {
			return err
		}
		if strings.HasPrefix(string(order.BaseToken), ibcDenomPrefix) {
			return refundIBCVoucher(order.BaseToken, string(order.Sender), order.BaseAmount)
		}
		return sendNative(string(order.BaseToken), string(order.Sender), order.BaseAmount)
	default:
		return errors.New("zkgm/v1: unsupported token order kind for refund")
	}
}

// refundIBCVoucher re-mints an IBC voucher to `recipient`, recovering the stored
// V2 metadata image so wrapped denom identity is preserved across ack/refund
// flows. Used by the UNESCROW market-maker fill ack, UNESCROW refund, and the
// ibc-denom branch of INITIALIZE/ESCROW refund.
func refundIBCVoucher(baseToken []byte, recipient string, amount *u256.Uint) error {
	baseDenom := string(baseToken)
	image, _ := zkgm.GetMetadataImageOf(baseDenom)
	return mintVoucher(cross, baseDenom, baseDenom, image, recipient, amount)
}

func sendNative(denom string, receiver string, amount *u256.Uint) error {
	n, err := amountInt64(amount)
	if err != nil {
		return err
	}

	b := banker.NewBanker(banker.BankerTypeRealmSend)
	b.SendCoins(runtime.CurrentRealm().Address(), address(receiver), chain.NewCoins(chain.NewCoin(denom, n)))

	return nil
}
