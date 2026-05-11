package main

import (
	"crypto/sha256"
	"encoding/binary"
	"encoding/hex"
	"fmt"
)

const (
	hashOpSHA256     = 1
	hashOpNoHash     = 0
	lengthOpVarProto = 1
	ibcStoreKey      = "ibc"

	wireTypeVarint = 0
	wireTypeBytes  = 2
)

type fixtureInput struct {
	name  string
	key   []byte
	value []byte
}

type fixture struct {
	input   fixtureInput
	subroot []byte
	appRoot []byte
	proofBz []byte
}

func main() {
	fixtures := []fixtureInput{
		{name: "packet", key: []byte("packet-key"), value: []byte("packet-value")},
		{name: "connection", key: []byte("connection-state-key"), value: []byte("connection-state-value")},
		{name: "channel", key: []byte("channel-state-key"), value: []byte("channel-state-value")},
	}
	for _, input := range fixtures {
		printFixture(makeMembershipFixture(input))
	}
}

func makeMembershipFixture(input fixtureInput) fixture {
	storeKey := []byte(ibcStoreKey)

	iavlLeaf := encodeLeafOp(
		hashOpSHA256,
		hashOpNoHash,
		hashOpSHA256,
		lengthOpVarProto,
		iavlLeafPrefix(),
	)
	iavlExist := encodeExistenceProof(input.key, input.value, iavlLeaf, nil)
	iavlRoot := applyLeaf(iavlLeafPrefix(), input.key, input.value)

	tmLeaf := encodeLeafOp(
		hashOpSHA256,
		hashOpNoHash,
		hashOpSHA256,
		lengthOpVarProto,
		[]byte{0x00},
	)
	tmExist := encodeExistenceProof(storeKey, iavlRoot, tmLeaf, nil)
	appRoot := applyLeaf([]byte{0x00}, storeKey, iavlRoot)

	proof := encodeMerkleProof(
		encodeCommitmentExist(iavlExist),
		encodeCommitmentExist(tmExist),
	)

	return fixture{
		input:   input,
		subroot: iavlRoot,
		appRoot: appRoot,
		proofBz: proof,
	}
}

func printFixture(f fixture) {
	fmt.Printf("[%s]\n", f.input.name)
	fmt.Printf("key: %q\n", f.input.key)
	fmt.Printf("value: %q\n", f.input.value)
	fmt.Printf("store_key: %q\n", []byte(ibcStoreKey))
	fmt.Printf("iavl_subroot: 0x%s\n", hex.EncodeToString(f.subroot))
	fmt.Printf("app_root: 0x%s\n", hex.EncodeToString(f.appRoot))
	fmt.Printf("membership_proof: 0x%s\n", hex.EncodeToString(f.proofBz))
	fmt.Println()
}

func applyLeaf(prefix, key, value []byte) []byte {
	valueHash := sha256.Sum256(value)
	preimage := append([]byte{}, prefix...)
	preimage = append(preimage, pbVarint(uint64(len(key)))...)
	preimage = append(preimage, key...)
	preimage = append(preimage, pbVarint(uint64(len(valueHash)))...)
	preimage = append(preimage, valueHash[:]...)
	root := sha256.Sum256(preimage)
	return root[:]
}

func iavlLeafPrefix() []byte {
	var out []byte
	out = binary.AppendVarint(out, 0) // height
	out = binary.AppendVarint(out, 1) // size
	out = binary.AppendVarint(out, 1) // version
	return out
}

func pbVarint(v uint64) []byte {
	return binary.AppendUvarint(nil, v)
}

func pbTag(fieldNum, wireType int) []byte {
	return pbVarint(uint64(fieldNum<<3 | wireType))
}

func pbBytesField(fieldNum int, data []byte) []byte {
	out := pbTag(fieldNum, wireTypeBytes)
	out = append(out, pbVarint(uint64(len(data)))...)
	return append(out, data...)
}

func pbVarintField(fieldNum int, v uint64) []byte {
	return append(pbTag(fieldNum, wireTypeVarint), pbVarint(v)...)
}

func encodeLeafOp(hash, prehashKey, prehashValue, length uint64, prefix []byte) []byte {
	var out []byte
	out = append(out, pbVarintField(1, hash)...)
	out = append(out, pbVarintField(2, prehashKey)...)
	out = append(out, pbVarintField(3, prehashValue)...)
	out = append(out, pbVarintField(4, length)...)
	out = append(out, pbBytesField(5, prefix)...)
	return out
}

func encodeExistenceProof(key, value, leaf []byte, innerOps [][]byte) []byte {
	var out []byte
	out = append(out, pbBytesField(1, key)...)
	out = append(out, pbBytesField(2, value)...)
	out = append(out, pbBytesField(3, leaf)...)
	for _, op := range innerOps {
		out = append(out, pbBytesField(4, op)...)
	}
	return out
}

func encodeCommitmentExist(epBytes []byte) []byte {
	return pbBytesField(1, epBytes)
}

func encodeMerkleProof(proofs ...[]byte) []byte {
	var out []byte
	for _, proof := range proofs {
		out = append(out, pbBytesField(1, proof)...)
	}
	return out
}
