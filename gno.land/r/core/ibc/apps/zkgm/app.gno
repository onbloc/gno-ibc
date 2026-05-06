package zkgm

import (
	"chain/runtime"
	"errors"

	"gno.land/p/aib/ibc/app"
	"gno.land/p/aib/ibc/types"
	z "gno.land/p/gnoswap/ibc/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
)

type App struct{}

var _ app.IBCApp = &App{}

func AsIBCApp() app.IBCApp {
	return &App{}
}

func (a *App) OnSendPacket(cur realm, sourceClient string, destinationClient string, sequence uint64, payload types.Payload) error {
	if paused {
		return errors.New("zkgm: paused")
	}
	if impl == nil {
		return errors.New("zkgm: impl not set")
	}
	return nil
}

func (a *App) OnRecvPacket(cur realm, sourceClient string, destinationClient string, sequence uint64, payload types.Payload) types.RecvPacketResult {
	if paused {
		return errAck(errors.New("zkgm: paused"))
	}
	if impl == nil {
		return errAck(errors.New("zkgm: impl not set"))
	}

	caller, relayer := originRelayer()
	req := RecvRequest{
		SourceClient:      sourceClient,
		DestinationClient: destinationClient,
		Sequence:          sequence,
		Payload:           payload,
		Caller:            caller,
		Relayer:           relayer,
	}
	if err := impl.PreRecv(req); err != nil {
		return errAck(err)
	}
	res, err := impl.Recv(req)
	if err != nil {
		return errAck(err)
	}
	impl.PostRecv(req, res)
	return res
}

func (a *App) OnTimeoutPacket(cur realm, sourceClient string, destinationClient string, sequence uint64, payload types.Payload) error {
	if paused {
		return errors.New("zkgm: paused")
	}
	if impl == nil {
		return errors.New("zkgm: impl not set")
	}
	caller, relayer := originRelayer()
	req := TimeoutRequest{
		SourceClient:      sourceClient,
		DestinationClient: destinationClient,
		Sequence:          sequence,
		Payload:           payload,
		Caller:            caller,
		Relayer:           relayer,
	}
	if err := impl.PreTimeout(req); err != nil {
		return err
	}
	if err := impl.Timeout(req); err != nil {
		return err
	}
	impl.PostTimeout(req)
	return nil
}

func (a *App) OnAcknowledgementPacket(cur realm, sourceClient string, destinationClient string, sequence uint64, acknowledgement []byte, payload types.Payload) error {
	if paused {
		return errors.New("zkgm: paused")
	}
	if impl == nil {
		return errors.New("zkgm: impl not set")
	}
	caller, relayer := originRelayer()
	req := AckRequest{
		SourceClient:      sourceClient,
		DestinationClient: destinationClient,
		Sequence:          sequence,
		Acknowledgement:   acknowledgement,
		Payload:           payload,
		Caller:            caller,
		Relayer:           relayer,
	}
	if err := impl.PreAck(req); err != nil {
		return err
	}
	if err := impl.Ack(req); err != nil {
		return err
	}
	impl.PostAck(req)
	return nil
}

// originRelayer returns the OriginCaller as both string (Caller) and bytes
// (Relayer). This is a placeholder until core IBC surfaces a distinct relayer
// identity and message; once it does, callers should populate the two fields
// independently.
func originRelayer() (caller string, relayer []byte) {
	s := runtime.OriginCaller().String()
	return s, []byte(s)
}

func errAck(err error) types.RecvPacketResult {
	ackBytes, encErr := z.EncodeAck(z.Ack{
		Tag:      u256.NewUint(0),
		InnerAck: []byte(err.Error()),
	})
	if encErr != nil {
		ackBytes = []byte(err.Error())
	}
	return types.RecvPacketResult{
		Status:          types.PacketStatus_Failure,
		Acknowledgement: ackBytes,
	}
}
