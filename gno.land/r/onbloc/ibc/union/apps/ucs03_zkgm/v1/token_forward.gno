package ucs03_zkgm

import (
	"gno.land/p/nt/fqname/v0"
	types "gno.land/p/onbloc/ibc/union/types"

	z "gno.land/p/onbloc/ibc/union/zkgm"
	u256 "gno.land/p/onbloc/math/uint256"
	"gno.land/r/onbloc/ibc/union/core"
)

func (v *ucs03ZkgmV1) executeTokenOrderForward(_ int, rlm realm, packet types.Packet, path *u256.Uint, order z.TokenOrderV2, relayer address, wrapped string) (types.RecvPacketResult, error) {
	handler, handlerAddr, _ := v.store.GetTokenForwardHandler()

	amount, serr := z.ScaleDownToInt64(order.QuoteAmount, v.scaleExpOf(wrapped))
	if serr != nil {
		return core.NewRecvPacketResult(types.PacketStatusUnknown, nil), serr
	}

	// grc20reg keys a voucher by fqname.Construct(registering realm, symbol),
	// not by its ibc/ denom (see grc20reg.Register / getOrCreateVoucher), so
	// derive it the same way to honor BaseTokenKey's "grc20reg key" contract.
	voucher, ok := v.store.GetVoucher(wrapped)
	if !ok {
		panic("ucs03_zkgm: voucher not found for forwarded denom " + wrapped)
	}
	baseTokenKey := fqname.Construct(rlm.PkgPath(), voucher.Token().GetSymbol())

	corrID := tokenForwardCorrID(packet)
	req := z.TokenForwardRequest{
		SourceChannel:      packet.SourceChannelId.String(),
		DestinationChannel: packet.DestinationChannelId.String(),
		Receiver:           handlerAddr.String(),
		Memo:               types.CloneBytes(order.Metadata),
		BaseTokenKey:       baseTokenKey,
		Amount:             amount,
	}

	// Validate before taking custody: a rejected forward returns an error ack
	// and refunds, with nothing minted.
	if perr := handler.Prepare(cross(rlm), req, corrID); perr != nil {
		return failureResult(universalErrorAck()), nil
	}

	// Take custody: mint to the handler and record the pending forward, then
	// hand off. Execute must panic on any failure past here so the whole
	// recv (mint included) reverts rather than acking over stranded funds;
	// the deferred ack is resolved later via CompleteTokenForwardAck.
	mintRes, merr := v.protocolFillMint(0, rlm, packet.DestinationChannelId, path, order.BaseToken, wrapped, handlerAddr, relayer, order.BaseAmount, order.QuoteAmount, nil, false)
	if merr != nil || mintRes.Status != types.PacketStatusSuccess {
		return mintRes, merr
	}

	v.store.SetPendingTokenForward(0, rlm, corrID, packet)
	handler.Execute(cross(rlm), req, corrID)

	return core.NewRecvPacketResult(types.PacketStatusAsync, nil), nil
}

// tokenForwardCorrID derives a corrID deterministically from the packet.
func tokenForwardCorrID(packet types.Packet) string {
	return types.MustCommit(types.CommitPacket(packet)).String()
}

// CompleteTokenForwardAck resolves the deferred ack once the handler's onward leg
// settles. Callable only by the registered forward handler.
func (v *ucs03ZkgmV1) CompleteTokenForwardAck(_ int, rlm realm, corrID string, success bool, innerAck []byte) {
	assertIsRlmCurrent(0, rlm)

	_, _, handlerPkgPath := v.store.GetTokenForwardHandler()
	if rlm.Previous().PkgPath() != handlerPkgPath {
		panic("ucs03_zkgm: caller is not the registered forward handler")
	}

	parent, found := v.store.GetPendingTokenForward(corrID)
	if !found {
		panic("ucs03_zkgm: no pending forward for corrID")
	}
	v.store.RemovePendingTokenForward(0, rlm, corrID)

	tag := tagAckFailure()
	if success {
		tag = tagAckSuccess()
	}

	ack, err := z.EncodeAck(z.Ack{Tag: tag, InnerAck: innerAck})
	if err != nil {
		panic(err.Error())
	}

	core.WriteAcknowledgement(cross(rlm), types.NewMsgWriteAcknowledgement(parent, ack))
}
