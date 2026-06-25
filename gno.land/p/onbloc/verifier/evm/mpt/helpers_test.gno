package mpt

import (
	"crypto/keccak256"

	"gno.land/p/onbloc/encoding/rlp"
)

func node(path []byte, valueOrRef []byte) []byte {
	return rlp.EncodeList(rlp.EncodeBytes(path), valueOrRef)
}

func emptyBranch() [][]byte {
	children := make([][]byte, 17)
	for i := range children {
		children[i] = rlp.EncodeBytes(nil)
	}
	return children
}

func branchWithValue(value []byte) []byte {
	children := emptyBranch()
	children[16] = value
	return rlp.EncodeList(children...)
}

func branchWithChild(index int, child []byte) []byte {
	children := emptyBranch()
	children[index] = child
	return rlp.EncodeList(children...)
}

func hash(encoded []byte) [32]byte {
	return keccak256.Sum256(encoded)
}

func hashBytes(encoded []byte) []byte {
	h := hash(encoded)
	return h[:]
}

func leafPath(nibbles []byte) []byte {
	return compactEncode(true, nibbles)
}

func extensionPath(nibbles []byte) []byte {
	return compactEncode(false, nibbles)
}

func compactEncode(leaf bool, nibbles []byte) []byte {
	flag := byte(0)
	if leaf {
		flag = 2
	}
	odd := len(nibbles)%2 == 1
	out := make([]byte, 0, (len(nibbles)+2)/2)
	if odd {
		out = append(out, (flag+1)<<4|nibbles[0])
		nibbles = nibbles[1:]
	} else {
		out = append(out, flag<<4)
	}
	for i := 0; i < len(nibbles); i += 2 {
		out = append(out, nibbles[i]<<4|nibbles[i+1])
	}
	return out
}
