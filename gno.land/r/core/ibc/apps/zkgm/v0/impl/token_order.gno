package impl

import (
	"bytes"
	"chain"
	"chain/banker"
	"chain/runtime"
	"errors"
	"strings"

	"gno.land/p/aib/ibc/types"
	z "gno.land/p/gnoswap/ibc/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
	zkgm "gno.land/r/gnoswap/ibc/apps/zkgm"
)

const (
	PortID         = "ucs03-zkgm-0"
	packetEncoding = "abi"
)

var (
	tagAckSuccess       = u256FromBytes32(z.TAG_ACK_SUCCESS)
	tagAckFailure       = u256FromBytes32(z.TAG_ACK_FAILURE)
	fillTypeProtocol    = u256FromBytes32(z.FILL_TYPE_PROTOCOL)
	fillTypeMarketMaker = u256FromBytes32(z.FILL_TYPE_MARKETMAKER)
)

func (v *ZkgmV0) sendTokenOrderV2(req zkgm.SendRequest) (zkgm.SendResult, error) {
	if req.Instruction.Version != z.INSTR_VERSION_2 {
		return zkgm.SendResult{}, errors.New("zkgm/v0: unsupported instruction version")
	}
	order, err := z.DecodeTokenOrderV2(req.Instruction.Operand)
	if err != nil {
		return zkgm.SendResult{}, err
	}
	if err := v.verifyTokenOrderV2(req.ChannelID, req.Sender, parseCoins(req.SentCoins), order); err != nil {
		return zkgm.SendResult{}, err
	}
	return v.sendPacket(req)
}

func (v *ZkgmV0) verifyTokenOrderV2(channelID string, sender string, sent chain.Coins, order z.TokenOrderV2) error {
	switch order.Kind {
	case z.TOKEN_ORDER_KIND_INITIALIZE, z.TOKEN_ORDER_KIND_ESCROW:
		baseDenom := string(order.BaseToken)
		if strings.HasPrefix(baseDenom, ibcDenomPrefix) {
			if err := burnVoucher(cross, baseDenom, sender, order.BaseAmount); err != nil {
				return err
			}
		} else if err := requireSentCoin(sent, baseDenom, order.BaseAmount); err != nil {
			return err
		}
		increaseChannelBalanceV2(cross, channelID, u256.Zero(), order.BaseToken, order.QuoteToken, order.BaseAmount)
		return nil
	case z.TOKEN_ORDER_KIND_UNESCROW:
		baseDenom := string(order.BaseToken)
		if strings.HasPrefix(baseDenom, ibcDenomPrefix) {
			return burnVoucher(cross, baseDenom, sender, order.BaseAmount)
		}
		return requireSentCoin(sent, baseDenom, order.BaseAmount)
	case z.TOKEN_ORDER_KIND_SOLVE:
		return errors.New("zkgm/v0: solve token order not implemented")
	default:
		return errors.New("zkgm/v0: unknown token order kind")
	}
}

func (v *ZkgmV0) executeTokenOrderV2(req zkgm.RecvRequest, path *u256.Uint, order z.TokenOrderV2) (types.RecvPacketResult, error) {
	switch order.Kind {
	case z.TOKEN_ORDER_KIND_INITIALIZE:
		if len(order.Metadata) == 0 {
			return types.RecvPacketResult{}, errors.New("zkgm/v0: initialize requires metadata")
		}
		meta, err := z.DecodeTokenMetadata(order.Metadata)
		if err != nil {
			return types.RecvPacketResult{}, err
		}
		image := MetadataImage(meta)
		ibcDenom := PredictWrappedTokenV2(req.DestinationClient, order.BaseToken, image)
		if err := mintVoucher(cross, ibcDenom, string(order.BaseToken), image, string(order.Receiver), order.QuoteAmount); err != nil {
			return types.RecvPacketResult{}, err
		}
		zkgm.SetTokenOrigin(cross, ibcDenom, path)
	case z.TOKEN_ORDER_KIND_ESCROW:
		ibcDenom := string(order.QuoteToken)
		image, ok := zkgm.GetMetadataImageOf(ibcDenom)
		if !ok {
			image = [32]byte{}
		}
		if err := mintVoucher(cross, ibcDenom, string(order.BaseToken), image, string(order.Receiver), order.QuoteAmount); err != nil {
			return types.RecvPacketResult{}, err
		}
	case z.TOKEN_ORDER_KIND_UNESCROW:
		if err := decreaseChannelBalanceV2(cross, req.DestinationClient, path, order.QuoteToken, order.BaseToken, order.QuoteAmount); err != nil {
			return types.RecvPacketResult{}, err
		}
		if err := sendNative(string(order.QuoteToken), string(order.Receiver), order.QuoteAmount); err != nil {
			return types.RecvPacketResult{}, err
		}
	case z.TOKEN_ORDER_KIND_SOLVE:
		return types.RecvPacketResult{}, errors.New("zkgm/v0: solve recv not implemented")
	default:
		return types.RecvPacketResult{}, errors.New("zkgm/v0: unknown token order kind")
	}
	innerAck, err := z.EncodeTokenOrderAck(z.TokenOrderAck{
		FillType:    fillTypeProtocol,
		MarketMaker: nil,
	})
	if err != nil {
		return types.RecvPacketResult{}, err
	}
	ack, err := z.EncodeAck(z.Ack{Tag: tagAckSuccess, InnerAck: innerAck})
	if err != nil {
		return types.RecvPacketResult{}, err
	}
	return types.RecvPacketResult{Status: types.PacketStatus_Success, Acknowledgement: ack}, nil
}

func (v *ZkgmV0) acknowledgeTokenOrderV2(sourceClient string, path *u256.Uint, order z.TokenOrderV2, ack z.Ack) error {
	if ack.Tag.Eq(tagAckFailure) {
		return v.refundV2(sourceClient, path, order)
	}
	if !ack.Tag.Eq(tagAckSuccess) {
		return errors.New("zkgm/v0: unknown ack tag")
	}
	orderAck, err := z.DecodeTokenOrderAck(ack.InnerAck)
	if err != nil {
		return err
	}
	if orderAck.FillType.Eq(fillTypeProtocol) {
		return nil
	}
	if !orderAck.FillType.Eq(fillTypeMarketMaker) {
		return errors.New("zkgm/v0: unknown fill type")
	}
	marketMaker := string(orderAck.MarketMaker)
	switch order.Kind {
	case z.TOKEN_ORDER_KIND_UNESCROW:
		return mintVoucher(cross, string(order.BaseToken), string(order.BaseToken), [32]byte{}, marketMaker, order.BaseAmount)
	case z.TOKEN_ORDER_KIND_INITIALIZE, z.TOKEN_ORDER_KIND_ESCROW:
		if err := decreaseChannelBalanceV2(cross, sourceClient, path, order.BaseToken, order.QuoteToken, order.BaseAmount); err != nil {
			return err
		}
		return sendNative(string(order.BaseToken), marketMaker, order.BaseAmount)
	default:
		return errors.New("zkgm/v0: unsupported token order kind for ack")
	}
}

func (v *ZkgmV0) refundV2(sourceClient string, path *u256.Uint, order z.TokenOrderV2) error {
	switch order.Kind {
	case z.TOKEN_ORDER_KIND_UNESCROW:
		return mintVoucher(cross, string(order.BaseToken), string(order.BaseToken), [32]byte{}, string(order.Sender), order.BaseAmount)
	case z.TOKEN_ORDER_KIND_INITIALIZE, z.TOKEN_ORDER_KIND_ESCROW:
		if err := decreaseChannelBalanceV2(cross, sourceClient, path, order.BaseToken, order.QuoteToken, order.BaseAmount); err != nil {
			return err
		}
		if strings.HasPrefix(string(order.BaseToken), ibcDenomPrefix) {
			return mintVoucher(cross, string(order.BaseToken), string(order.BaseToken), [32]byte{}, string(order.Sender), order.BaseAmount)
		}
		return sendNative(string(order.BaseToken), string(order.Sender), order.BaseAmount)
	default:
		return errors.New("zkgm/v0: unsupported token order kind for refund")
	}
}

func sendNative(denom string, receiver string, amount *u256.Uint) error {
	b := banker.NewBanker(banker.BankerTypeRealmSend)
	b.SendCoins(runtime.CurrentRealm().Address(), address(receiver), chain.NewCoins(chain.NewCoin(denom, amountInt64(amount))))
	return nil
}

func u256FromBytes32(bz [32]byte) *u256.Uint {
	return new(u256.Uint).SetBytes(bz[:])
}

func decodePacket(payload types.Payload) (z.ZkgmPacket, error) {
	return z.DecodeZkgmPacket(payload.Value)
}

func decodeOrder(packet z.ZkgmPacket) (z.TokenOrderV2, error) {
	if packet.Instruction.Version != z.INSTR_VERSION_2 {
		return z.TokenOrderV2{}, errors.New("zkgm/v0: unsupported instruction version")
	}
	return z.DecodeTokenOrderV2(packet.Instruction.Operand)
}

func isUniversalErrorAck(ack []byte) bool {
	return bytes.Equal(ack, types.UniversalErrorAcknowledgement())
}
