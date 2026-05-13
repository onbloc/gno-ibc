package impl

import (
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
	errInvalidUnescrow  = errors.New("zkgm/v0: invalid token order unescrow")
)

func (v *ZkgmV0) sendTokenOrderV2(req zkgm.SendRequest) (zkgm.SendResult, error) {
	if req.Instruction.Version != z.INSTR_VERSION_2 {
		return zkgm.SendResult{}, errors.New("zkgm/v0: unsupported instruction version")
	}
	order, err := z.DecodeTokenOrderV2(req.Instruction.Operand)
	if err != nil {
		return zkgm.SendResult{}, err
	}
	if err := v.verifyTokenOrderV2(req.ChannelID, req.Sender, parseCoins(req.SentCoins), u256.Zero(), order); err != nil {
		return zkgm.SendResult{}, err
	}
	return v.sendPacket(req)
}

func (v *ZkgmV0) verifyTokenOrderV2(channelID string, sender string, sent chain.Coins, path *u256.Uint, order z.TokenOrderV2) error {
	if path == nil {
		path = u256.Zero()
	}
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
		increaseChannelBalanceV2(cross, channelID, path, order.BaseToken, order.QuoteToken, order.BaseAmount)
		return nil
	case z.TOKEN_ORDER_KIND_UNESCROW:
		baseDenom := string(order.BaseToken)
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
		if channelID != channelToClient(destChan) {
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
		return errors.New("zkgm/v0: solve token order not implemented")
	default:
		return errors.New("zkgm/v0: unknown token order kind")
	}
}

func (v *ZkgmV0) executeTokenOrderV2(req zkgm.RecvRequest, path *u256.Uint, order z.TokenOrderV2) (types.RecvPacketResult, error) {
	if path == nil {
		path = u256.Zero()
	}
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
		destChan, err := tokenOrderDestinationChannel(req.DestinationClient)
		if err != nil {
			return types.RecvPacketResult{}, err
		}
		ibcDenom := PredictWrappedTokenV2(path, destChan, order.BaseToken, image)
		if string(order.QuoteToken) != ibcDenom || order.BaseAmount.Cmp(order.QuoteAmount) < 0 {
			return failureResult(universalErrorAck()), nil
		}
		fee := new(u256.Uint).Sub(order.BaseAmount, order.QuoteAmount)
		if _, err := amountInt64(order.QuoteAmount); err != nil {
			return types.RecvPacketResult{}, err
		}
		if _, err := amountInt64(fee); err != nil {
			return types.RecvPacketResult{}, err
		}
		nextPath, err := z.UpdateChannelPath(path, destChan)
		if err != nil {
			return types.RecvPacketResult{}, err
		}
		if !order.QuoteAmount.IsZero() {
			if err := mintVoucher(cross, ibcDenom, string(order.BaseToken), image, string(order.Receiver), order.QuoteAmount); err != nil {
				return types.RecvPacketResult{}, err
			}
		}
		if !fee.IsZero() {
			if err := mintVoucher(cross, ibcDenom, string(order.BaseToken), image, recvRelayer(req), fee); err != nil {
				return types.RecvPacketResult{}, err
			}
		}
		zkgm.SetTokenOrigin(cross, ibcDenom, nextPath)
	case z.TOKEN_ORDER_KIND_ESCROW:
		quoteDenom := string(order.QuoteToken)
		image, hasImage := zkgm.GetMetadataImageOf(quoteDenom)
		destChan, err := tokenOrderDestinationChannel(req.DestinationClient)
		if err != nil {
			return types.RecvPacketResult{}, err
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
			return types.RecvPacketResult{}, err
		}
		if _, err := amountInt64(fee); err != nil {
			return types.RecvPacketResult{}, err
		}
		_, hasOrigin := zkgm.GetTokenOrigin(quoteDenom)
		var nextPath *u256.Uint
		if !hasOrigin {
			nextPath, err = z.UpdateChannelPath(path, destChan)
			if err != nil {
				return types.RecvPacketResult{}, err
			}
		}
		if !order.QuoteAmount.IsZero() {
			if err := mintVoucher(cross, quoteDenom, string(order.BaseToken), image, string(order.Receiver), order.QuoteAmount); err != nil {
				return types.RecvPacketResult{}, err
			}
		}
		if !fee.IsZero() {
			if err := mintVoucher(cross, quoteDenom, string(order.BaseToken), image, recvRelayer(req), fee); err != nil {
				return types.RecvPacketResult{}, err
			}
		}
		if !hasOrigin {
			zkgm.SetTokenOrigin(cross, quoteDenom, nextPath)
		}
	case z.TOKEN_ORDER_KIND_UNESCROW:
		reversedPath, err := z.ReverseChannelPath(path)
		if err != nil {
			return types.RecvPacketResult{}, err
		}
		if order.BaseAmount.Cmp(order.QuoteAmount) < 0 {
			return types.RecvPacketResult{}, errors.New("zkgm/v0: base amount below quote amount")
		}
		fee := new(u256.Uint).Sub(order.BaseAmount, order.QuoteAmount)
		if _, err := amountInt64(order.BaseAmount); err != nil {
			return types.RecvPacketResult{}, err
		}
		if _, err := amountInt64(order.QuoteAmount); err != nil {
			return types.RecvPacketResult{}, err
		}
		if _, err := amountInt64(fee); err != nil {
			return types.RecvPacketResult{}, err
		}
		if err := decreaseChannelBalanceV2(cross, req.DestinationClient, reversedPath, order.QuoteToken, order.BaseToken, order.BaseAmount); err != nil {
			return types.RecvPacketResult{}, err
		}
		if !order.QuoteAmount.IsZero() {
			if err := sendNative(string(order.QuoteToken), string(order.Receiver), order.QuoteAmount); err != nil {
				return types.RecvPacketResult{}, err
			}
		}
		if !fee.IsZero() {
			if err := sendNative(string(order.QuoteToken), recvRelayer(req), fee); err != nil {
				return types.RecvPacketResult{}, err
			}
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
		return refundIBCVoucher(order.BaseToken, marketMaker, order.BaseAmount)
	case z.TOKEN_ORDER_KIND_INITIALIZE, z.TOKEN_ORDER_KIND_ESCROW:
		if _, err := amountInt64(order.BaseAmount); err != nil {
			return err
		}
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
		return refundIBCVoucher(order.BaseToken, string(order.Sender), order.BaseAmount)
	case z.TOKEN_ORDER_KIND_INITIALIZE, z.TOKEN_ORDER_KIND_ESCROW:
		if _, err := amountInt64(order.BaseAmount); err != nil {
			return err
		}
		if err := decreaseChannelBalanceV2(cross, sourceClient, path, order.BaseToken, order.QuoteToken, order.BaseAmount); err != nil {
			return err
		}
		if strings.HasPrefix(string(order.BaseToken), ibcDenomPrefix) {
			return refundIBCVoucher(order.BaseToken, string(order.Sender), order.BaseAmount)
		}
		return sendNative(string(order.BaseToken), string(order.Sender), order.BaseAmount)
	default:
		return errors.New("zkgm/v0: unsupported token order kind for refund")
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

func u256FromBytes32(bz [32]byte) *u256.Uint {
	return new(u256.Uint).SetBytes(bz[:])
}

func decodePacket(payload types.Payload) (z.ZkgmPacket, error) {
	return z.DecodeZkgmPacket(payload.Value)
}

func decodeOrderInstruction(instr z.Instruction) (z.TokenOrderV2, error) {
	if instr.Version != z.INSTR_VERSION_2 {
		return z.TokenOrderV2{}, errors.New("zkgm/v0: unsupported instruction version")
	}
	return z.DecodeTokenOrderV2(instr.Operand)
}

func tokenOrderDestinationChannel(clientID string) (uint32, error) {
	destChan, ok := clientToChannel(clientID)
	if !ok || destChan == 0 {
		return 0, errors.New("zkgm/v0: invalid token order destination client")
	}
	return destChan, nil
}

func recvRelayer(req zkgm.RecvRequest) string {
	if req.Caller != "" {
		return req.Caller
	}
	return string(req.Relayer)
}
