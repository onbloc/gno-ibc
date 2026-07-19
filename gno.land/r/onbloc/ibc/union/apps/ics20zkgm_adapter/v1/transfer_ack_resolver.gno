package ics20zkgm_adapter

import (
	"gno.land/r/aib/ibc/apps/transfer"
	adapter "gno.land/r/onbloc/ibc/union/apps/ics20zkgm_adapter"
)

// TransferAckResolver implements adapter.TransferAckResolver by delegating to
// the real transfer.WriteHookAck. Install once via
// adapter.SetTransferAckResolver(cross(cur), NewTransferAckResolver()).
type TransferAckResolver struct{}

var _ adapter.TransferAckResolver = (*TransferAckResolver)(nil)

// NewTransferAckResolver constructs a TransferAckResolver. Foreign realms
// (e.g. an admin deploy script) must go through this instead of a struct
// literal — see NewDenomConfig's doc comment for why.
func NewTransferAckResolver() *TransferAckResolver {
	return &TransferAckResolver{}
}

func (*TransferAckResolver) WriteHookAck(cur realm, sourceClient string, sequence uint64, success bool) error {
	return transfer.WriteHookAck(cross(cur), sourceClient, sequence, success)
}
