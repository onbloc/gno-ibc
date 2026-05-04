package zkgm

// Zkgmable is implemented by realms that receive ZKGM Call instructions
// dispatched from the ZKGM proxy.
type Zkgmable interface {
	// OnZkgm handles a standard ZKGM Call.
	OnZkgm(cur realm, sender []byte, calldata []byte) error

	// OnIntentZkgm handles the intent-settlement Call variant.
	OnIntentZkgm(cur realm, sender []byte, calldata []byte) error
}
