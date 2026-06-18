package cometbls

const (
	ModuleName = "11-cometbls"

	ClientType = ModuleName
)

var moduleKey = []byte("wasm")

func makeStoreKey(addr H256, key []byte) []byte {
	out := make([]byte, 0, 1+32+1+len(key))
	out = append(out, 0x03)
	out = append(out, addr[:]...)
	out = append(out, 0x00)
	out = append(out, key...)

	return out
}
