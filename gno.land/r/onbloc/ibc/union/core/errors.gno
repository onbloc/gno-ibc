package core

import "errors"

var (
	ErrClientNotActive               = errors.New("client is not active")
	ErrInvalidConnectionState        = errors.New("invalid connection state")
	ErrInvalidChannelState           = errors.New("invalid channel state")
	ErrSyncAckEmpty                  = errors.New("sync ack cannot be empty")
	ErrUnknownPacketStatus           = errors.New("unknown packet status")
	ErrUnauthorizedAckWriter         = errors.New("caller not authorized to write ack")
	ErrAcknowledgementAlreadyWritten = errors.New("acknowledgement already written")
	ErrAcknowledgementEmpty          = errors.New("acknowledgement cannot be empty")
	ErrUnauthorizedPacketSender      = errors.New("caller not authorized to send packet")
	ErrPacketReceiptNotFound         = errors.New("packet receipt not found")
	ErrNotEnoughPackets              = errors.New("not enough packets")
	ErrBatchSameChannelOnly          = errors.New("batch must use the same channel")
	ErrAcknowledgementCountMismatch  = errors.New("acknowledgement count mismatch")
	ErrPortAlreadyRegistered         = errors.New("port already registered")
	ErrBatchPacketsNotFound          = errors.New("batch packets not found")
	ErrBatchReceiptsNotFound         = errors.New("batch receipts not found")
	ErrPacketAlreadyReceived         = errors.New("packet already received")
	ErrPacketTimeoutExpired          = errors.New("packet timeout expired")
	ErrPacketTimeoutNotReached       = errors.New("packet timeout not reached")
	ErrIntentNotSupported            = errors.New("intent receive not supported")
)
