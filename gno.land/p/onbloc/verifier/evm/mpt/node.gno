package mpt

import (
	"gno.land/p/onbloc/encoding/rlp"
)

// isDataNode reports whether v is a string/byte payload rather than a list.
func isDataNode(v rlp.Value) bool {
	return v.Kind == rlp.KindString || v.Kind == rlp.KindByte
}

// node mirrors go-ethereum's node interface (marker only; cache/encode/
// fstring are for trie construction, unneeded for verification).
// Reference:
// https://github.com/ethereum/go-ethereum/blob/v1.10.26/trie/node.go#L30-L48
type node interface{}

// flags nodeFlag (cached hash + dirty bit, for incremental rehashing on
// mutation) is dropped from both structs below: never read by decodeNode,
// get, or verifyProof.
type (
	fullNode struct {
		Children [17]node
	}
	shortNode struct {
		Key []byte
		Val node
	}
	hashNode  []byte
	valueNode []byte
)

// decodeNode mirrors decodeNode (hash argument dropped: cache-only, unused
// by verification).
// Reference:
// https://github.com/ethereum/go-ethereum/blob/v1.10.26/trie/node.go#L133-L151
func decodeNode(buf []byte) (node, error) {
	v, err := rlp.DecodeValue(buf)
	if err != nil {
		return nil, err
	}

	return decodeNodeValue(v)
}

// decodeNodeValue is decodeNode's dispatch step, split out so decodeRef can
// resolve an already-decoded embedded child without re-parsing raw bytes.
func decodeNodeValue(v rlp.Value) (node, error) {
	if v.Kind != rlp.KindList {
		return nil, ErrUnexpectedNode
	}

	switch len(v.List) {
	case 2:
		return decodeShort(v)
	case 17:
		return decodeFull(v)
	default:
		return nil, ErrUnexpectedNode
	}
}

// decodeShort mirrors decodeShort.
// Reference:
// https://github.com/ethereum/go-ethereum/blob/v1.10.26/trie/node.go#L153-L173
func decodeShort(elems rlp.Value) (node, error) {
	kbuf := elems.List[0]
	if !isDataNode(kbuf) {
		return nil, ErrUnexpectedNode
	}

	key := compactToHex(kbuf.Bytes)

	if hasTerm(key) {
		val := elems.List[1]
		if !isDataNode(val) {
			return nil, ErrUnexpectedNode
		}

		// A leaf's value is mandatory (branch's 17th slot is optional): empty
		// here is a real empty value, not absence.
		// https://github.com/unionlabs/union/blob/031785bb6dc6b957c624e62bc64c184409c97d7b/lib/evm-storage-verifier/src/rlp_node_codec.rs#L168-L204
		// https://github.com/paritytech/trie/blob/0b9bede27b33da6395e83ed13c523ed2ae913fc6/trie-db/src/lookup.rs#L792-L834
		return &shortNode{Key: key, Val: valueNode(val.Bytes)}, nil
	}

	r, err := decodeRef(elems.List[1])
	if err != nil {
		return nil, err
	}

	return &shortNode{Key: key, Val: r}, nil
}

// decodeFull mirrors decodeFull.
// Reference:
// https://github.com/ethereum/go-ethereum/blob/v1.10.26/trie/node.go#L175-L192
func decodeFull(elems rlp.Value) (*fullNode, error) {
	n := &fullNode{}

	for i := 0; i < 16; i++ {
		cld, err := decodeRef(elems.List[i])
		if err != nil {
			return n, err
		}

		n.Children[i] = cld
	}

	val := elems.List[16]
	if !isDataNode(val) {
		return n, ErrUnexpectedNode
	}

	// A branch's 17th slot is an optional value; empty means none stored here.
	if len(val.Bytes) > 0 {
		n.Children[16] = valueNode(val.Bytes)
	}

	return n, nil
}

// decodeRef mirrors decodeRef, minus its "oversized embedded node" size
// check (no verifier-side security benefit: the parent hash already covers
// these bytes regardless of embed size).
// Reference:
// https://github.com/ethereum/go-ethereum/blob/v1.10.26/trie/node.go#L196-L218
func decodeRef(buf rlp.Value) (node, error) {
	if buf.Kind == rlp.KindList {
		return decodeNodeValue(buf)
	}

	switch len(buf.Bytes) {
	case 0:
		return nil, nil

	case 32:
		return hashNode(buf.Bytes), nil

	default:
		return nil, ErrInvalidReference
	}
}
