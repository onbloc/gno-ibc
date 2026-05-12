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
)

func (v *ZkgmV1) verifyTokenOrderV2(channelId core.ChannelId, sender string, sent chain.Coins, order z.TokenOrderV2) error {
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

		increaseChannelBalanceV2(cross, channelId, u256.Zero(), order.BaseToken, order.QuoteToken, order.BaseAmount)
		return nil
	case z.TOKEN_ORDER_KIND_UNESCROW:
		baseDenom := string(order.BaseToken)
		if err := zkgm.RateLimit(cross, baseDenom, order.BaseAmount); err != nil {
			return err
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

func (v *ZkgmV1) executeTokenOrderV2(packet core.Packet, path *u256.Uint, order z.TokenOrderV2) (core.RecvPacketResult, error) {
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
		ibcDenom := PredictWrappedTokenV2(packet.DestinationChannelId, order.BaseToken, image)
		if err := mintVoucher(cross, ibcDenom, string(order.BaseToken), image, string(order.Receiver), order.QuoteAmount); err != nil {
			return core.RecvPacketResult{}, err
		}

		zkgm.SetTokenOrigin(cross, ibcDenom, path)
	case z.TOKEN_ORDER_KIND_ESCROW:
		ibcDenom := string(order.QuoteToken)
		image, ok := zkgm.GetMetadataImageOf(ibcDenom)
		if !ok {
			image = [32]byte{}
		}
		if err := mintVoucher(cross, ibcDenom, string(order.BaseToken), image, string(order.Receiver), order.QuoteAmount); err != nil {
			return core.RecvPacketResult{}, err
		}
	case z.TOKEN_ORDER_KIND_UNESCROW:
		if err := decreaseChannelBalanceV2(cross, packet.DestinationChannelId, path, order.QuoteToken, order.BaseToken, order.QuoteAmount); err != nil {
			return core.RecvPacketResult{}, err
		}
		if err := sendNative(string(order.QuoteToken), string(order.Receiver), order.QuoteAmount); err != nil {
			return core.RecvPacketResult{}, err
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
		return mintVoucher(cross, string(order.BaseToken), string(order.BaseToken), [32]byte{}, marketMaker, order.BaseAmount)
	case z.TOKEN_ORDER_KIND_INITIALIZE, z.TOKEN_ORDER_KIND_ESCROW:
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
		return mintVoucher(cross, string(order.BaseToken), string(order.BaseToken), [32]byte{}, string(order.Sender), order.BaseAmount)
	case z.TOKEN_ORDER_KIND_INITIALIZE, z.TOKEN_ORDER_KIND_ESCROW:
		if err := decreaseChannelBalanceV2(cross, sourceChannelId, path, order.BaseToken, order.QuoteToken, order.BaseAmount); err != nil {
			return err
		}
		if strings.HasPrefix(string(order.BaseToken), ibcDenomPrefix) {
			return mintVoucher(cross, string(order.BaseToken), string(order.BaseToken), [32]byte{}, string(order.Sender), order.BaseAmount)
		}
		return sendNative(string(order.BaseToken), string(order.Sender), order.BaseAmount)
	default:
		return errors.New("zkgm/v1: unsupported token order kind for refund")
	}
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
