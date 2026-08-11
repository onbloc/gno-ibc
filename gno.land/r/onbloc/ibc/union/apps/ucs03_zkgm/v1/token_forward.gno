package ucs03_zkgm

import (
	"gno.land/p/nt/fqname/v0"
	types "gno.land/p/onbloc/ibc/union/types"

	z "gno.land/p/onbloc/ibc/union/zkgm"
	u256 "gno.land/p/onbloc/math/uint256"
	"gno.land/r/onbloc/ibc/union/core"
)

func (v *ucs03ZkgmV1) executeTokenOrderForward(_ int, rlm realm, packet types.Packet, path *u256.Uint, order z.TokenOrderV2, relayer address, wrapped string, meta z.TokenMetadata, metaPresent bool) (types.RecvPacketResult, error) {
	// Reject fee-bearing forwards: a relayer fee mint can't be unwound by
	// CompleteTokenForwardAck's failure-path burn, so it'd go uncollateralized.
	if order.BaseAmount.Cmp(order.QuoteAmount) != 0 {
		return failureResult(universalErrorAck()), nil
	}

	handler, handlerAddr, _ := v.store.GetTokenForwardHandler()

	// grc20reg keys a voucher by fqname.Construct(registering realm, symbol),
	// not by its ibc/ denom (see grc20reg.Register / getOrCreateVoucher), so
	// derive it the same way to honor BaseTokenKey's "grc20reg key" contract.
	var (
		baseTokenKey string
		scaleExp     int
	)

	if voucher, ok := v.store.GetVoucher(wrapped); ok {
		baseTokenKey = fqname.Construct(rlm.PkgPath(), voucher.Token().GetSymbol())
		scaleExp = voucher.ScaleExp()
	} else if metaPresent {
		// First sighting: predict the symbol/scale getOrCreateVoucher will assign below.
		ti, terr := z.DecodeTokenInitializer(meta.Initializer)
		if terr != nil {
			return failureResult(universalErrorAck()), nil
		}

		baseTokenKey = fqname.Construct(rlm.PkgPath(), sanitizeVoucherSymbol(ti.Symbol, wrapped))
		scaleExp = scaleExpForDecimals(ti.Decimals)
	} else {
		// Unreachable: token_order.gno rejects this case before calling here.
		panic("ucs03_zkgm: forward target has no voucher and no deploy metadata")
	}

	amount, serr := z.ScaleDownToInt64(order.QuoteAmount, scaleExp)
	if serr != nil {
		return core.NewRecvPacketResult(types.PacketStatusUnknown, nil), serr
	}

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

	var metadata *z.TokenMetadata
	if metaPresent {
		metadata = &meta
	}

	// Take custody: mint to the handler and record the pending forward, then
	// hand off. Execute must panic on any failure past here so the whole
	// recv (mint included) reverts rather than acking over stranded funds;
	// the deferred ack is resolved later via CompleteTokenForwardAck.
	mintRes, merr := v.protocolFillMint(0, rlm, packet.DestinationChannelId, path, order.BaseToken, wrapped, handlerAddr, relayer, order.BaseAmount, order.QuoteAmount, metadata, metaPresent)
	if merr != nil || mintRes.Status != types.PacketStatusSuccess {
		return mintRes, merr
	}

	v.store.SetPendingTokenForward(0, rlm, corrID, packet, wrapped, handlerAddr, order.QuoteAmount.Clone())
	callForwardHandlerExecute(0, rlm, handler, req, corrID)

	return core.NewRecvPacketResult(types.PacketStatusAsync, nil), nil
}

// callForwardHandlerExecute converts any panic from the handler's Execute
// into execFatal, since it runs in another realm and can't do so itself;
// otherwise dispatchExecutePacket's recover would absorb it into a failure
// ack instead of reverting the mint.
func callForwardHandlerExecute(_ int, rlm realm, handler z.TokenForwardHandler, req z.TokenForwardRequest, corrID string) {
	defer func() {
		if r := recover(); r != nil {
			panic(execFatal{extractPanicMessage(r)})
		}
	}()

	handler.Execute(cross(rlm), req, corrID)
}

// tokenForwardCorrID derives a corrID deterministically from the packet.
func tokenForwardCorrID(packet types.Packet) string {
	return types.MustCommit(types.CommitPacket(packet)).String()
}

// CompleteTokenForwardAck resolves the deferred ack once the handler's
// onward leg settles. Callable only by the registered forward handler.
// On failure it burns the voucher the onward protocol refunded to the
// handler, so the upstream refund isn't double-counted.
func (v *ucs03ZkgmV1) CompleteTokenForwardAck(_ int, rlm realm, corrID string, success bool, innerAck []byte) {
	assertIsRlmCurrent(0, rlm)

	_, _, handlerPkgPath := v.store.GetTokenForwardHandler()
	if rlm.Previous().PkgPath() != handlerPkgPath {
		panic("ucs03_zkgm: caller is not the registered forward handler")
	}

	parent, wrapped, handlerAddr, amount, found := v.store.GetPendingTokenForward(corrID)
	if !found {
		panic("ucs03_zkgm: no pending forward for corrID")
	}

	// parent.Data and amount are readonly-tainted (non-crossing getter into the proxy's store);
	// use them fully before removing the entry (removal can invalidate their backing objects).
	parent.Data = types.CloneBytes(parent.Data)

	// innerAck is the onward ICS20 leg's own ack (e.g. `{"result":"AQ=="}`), not a
	// Union TokenOrderAck. The EVM side only decodes InnerAck as TokenOrderAck when
	// the outer tag is success (see TokenOrder.sol's _acknowledgeTokenOrderV1 — the
	// failure branch ignores ack entirely and refunds from order fields instead), so
	// only the success case needs replacing with a real protocol-fill TokenOrderAck.
	tag := tagAckFailure()
	ackPayload := innerAck
	if success {
		tag = tagAckSuccess()

		encoded, err := z.EncodeTokenOrderAck(z.TokenOrderAck{FillType: fillTypeProtocol(), MarketMaker: nil})
		if err != nil {
			panic(err.Error())
		}
		ackPayload = encoded
	} else {
		if err := v.burnVoucher(0, rlm, wrapped, handlerAddr, amount); err != nil {
			panic("ucs03_zkgm: token forward refund burn failed: " + err.Error())
		}
	}

	v.store.RemovePendingTokenForward(0, rlm, corrID)

	ack, err := z.EncodeAck(z.Ack{Tag: tag, InnerAck: ackPayload})
	if err != nil {
		panic(err.Error())
	}

	core.WriteAcknowledgement(cross(rlm), types.NewMsgWriteAcknowledgement(parent, ack))
}
