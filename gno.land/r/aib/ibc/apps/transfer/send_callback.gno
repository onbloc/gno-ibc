package transfer

// Outbound counterpart to forward.gno: lets the registered ForwardHandler
// realm send on its own behalf and be notified of the ack/timeout outcome.
// Mirrors zkgm.SendCallback/SendWithCallback.

import (
	"chain"
	"strconv"

	"gno.land/p/aib/ibc/types"
	"gno.land/p/nt/ufmt/v0"
	"gno.land/r/aib/ibc/core"
	"gno.land/r/demo/defi/grc20reg"
)

// SendCallback is implemented by a realm that wants to be notified of the
// ack/timeout outcome of a packet it sent via TransferWithCallback. corrID is
// echoed back verbatim from what was passed to TransferWithCallback.
type SendCallback interface {
	OnTransferSendResult(cur realm, corrID string, success bool, ack []byte) error
}

// pendingHandlerSend authorizes OnSendPacket's signer check for the duration
// of TransferWithCallback's core.SendPacket call, since the packet Sender is
// the handler's realm address rather than a signing EOA.
var pendingHandlerSend bool

// TransferWithCallback sends a registered GRC20 token the caller already
// holds. Only the registered forward handler may call it; the packet Sender
// is the handler's own address so a failure refund lands back on it.
func TransferWithCallback(cur realm, clientID, receiver, denom string, amount int64, timeoutTimestamp uint64, memo string, corrID string, cb SendCallback) (
	packet types.MsgSendPacket, sequence uint64,
) {
	if cb == nil {
		panic("transfer: TransferWithCallback requires a non-nil callback")
	}

	caller := cur.Previous()
	if caller.PkgPath() != forwardHandlerPkgPath {
		panic("transfer: TransferWithCallback caller is not the registered forward handler")
	}
	if grc20reg.Get(denom) == nil {
		panic(ufmt.Sprintf("transfer: TransferWithCallback requires a registered GRC20 denom, got %s", denom))
	}

	sender := caller.Address().String()
	alias := GRC20Alias(denom)
	pendingGRC20Send = &pendingSend{
		sender:       sender,
		sourceClient: clientID,
		denom:        alias,
		amount:       amount,
	}
	pendingHandlerSend = true
	defer func() {
		pendingGRC20Send = nil
		pendingHandlerSend = false
	}()

	data := NewFungibleTokenPacketData(alias, ufmt.Sprintf("%d", amount), sender, receiver, memo)
	packet = types.MsgSendPacket{
		SourceClient: clientID,
		Payloads: []types.Payload{{
			SourcePort:      PortID,
			DestinationPort: PortID,
			Encoding:        EncodingProtobuf,
			Value:           data.ProtoMarshal(),
			Version:         V1,
		}},
		TimeoutTimestamp: timeoutTimestamp,
	}
	sequence = core.SendPacket(cross(cur), packet)

	setPendingSendCorr(clientID, sequence, pendingSendCorr{Callback: cb, CallerPkgPath: caller.PkgPath(), CorrID: corrID})
	return packet, sequence
}

// handleSendCallback detects a packet sent via TransferWithCallback resolving
// on ack/timeout and notifies the registered caller, mirroring ZKGM's
// handleSendCallback. A notification failure panics, like the rest of a
// failed ack/timeout tx.
func handleSendCallback(cur realm, sourceClient string, sequence uint64, success bool, ack []byte) bool {
	p := getPendingSendCorr(sourceClient, sequence)
	if p.Callback == nil {
		return false
	}
	removePendingSendCorr(sourceClient, sequence)

	if err := p.Callback.OnTransferSendResult(cross(cur), p.CorrID, success, ack); err != nil {
		panic(err.Error())
	}

	chain.Emit(
		EventTypeSendResultDelivered,
		AttributeKeyCallerPkgPath, p.CallerPkgPath,
		AttributeKeyCorrID, p.CorrID,
		AttributeKeyAckSuccess, strconv.FormatBool(success),
	)
	return true
}
