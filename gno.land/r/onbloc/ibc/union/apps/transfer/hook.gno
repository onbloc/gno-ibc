package transfer

// TransferHook is called after a successful ICS20 mint (when the sender chain
// is the source). Returning an error panics the recv, rolling back the entire
// transaction atomically — no tokens are minted.
type TransferHook interface {
	Address() address
	OnTransferRecv(cur realm, data FungibleTokenPacketData, denom Denom) error
}

var (
	hook       TransferHook
	hookCaller address
)
