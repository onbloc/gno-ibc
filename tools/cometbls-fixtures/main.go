package main

import (
	"bytes"
	"crypto/sha256"
	"encoding/binary"
	"encoding/hex"
	"fmt"
	"sort"
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
	name             string
	key              []byte
	value            []byte
	nonMembershipKey []byte
}

type fixture struct {
	input              fixtureInput
	subroot            []byte
	appRoot            []byte
	proofBz            []byte
	nonMembershipProof []byte
}

type iavlLeafNode struct {
	input    fixtureInput
	inputIdx int
	hash     []byte
	proof    [][]byte
}

type iavlNode struct {
	hash   []byte
	height int64
	size   int64
	leaves []*iavlLeafNode
}

func main() {
	baseFixtures := []fixtureInput{
		{
			name:             "packet",
			key:              []byte("packet-key"),
			value:            []byte("packet-value"),
			nonMembershipKey: []byte("packet-key-missing"),
		},
		{name: "connection", key: []byte("connection-state-key"), value: []byte("connection-state-value")},
		{name: "channel", key: []byte("channel-state-key"), value: []byte("channel-state-value")},
	}
	z35Fixtures := []fixtureInput{
		{
			name:  "z35_connection_try",
			key:   mustHex("05f3c8eef62e74b10b7ee910fcc73c8358000f692d9ce2341a989e008e45b35d"),
			value: mustHex("ff4fb67348c16e70c898c7cf43c460a684bc900d2b41e5a24ef6dcb294586034"),
		},
		{
			name:  "z35_channel_try",
			key:   mustHex("88601476d11616a71c5be67555bd1dff4b1cbf21533d2669b768b61518cfe1c3"),
			value: mustHex("fa3c11d224a164cd0beca2b6756128dc1531714a75813e9c2b5840bd8f2a8347"),
		},
		{
			name:  "z35_packet_commitment",
			key:   mustHex("cd7b438a4f36b68a13ce77733e104cbf38a4bd2460f5a35d75a5aa0180b951cc"),
			value: mustHex("0100000000000000000000000000000000000000000000000000000000000000"),
		},
		{
			name:  "z36_ack_membership",
			key:   mustHex("3cde3b6891df12ae3a04f23e62738b1c7e209ddb5a5dd6ebc27b6c29cd539b18"),
			value: mustHex("015b3cd48177600c2efac9e26b978edfdf97f8480c0a7f3b0884f0b4817ed5a8"),
		},
		{
			name:  "z39_call_packet_commitment",
			key:   mustHex("ecfa376e2392e124e1633138b49b4ca5920159120ec4106c2a559b5b674b0b30"),
			value: mustHex("0100000000000000000000000000000000000000000000000000000000000000"),
		},
		{
			name:  "z39_missing_call_packet_commitment",
			key:   mustHex("5abf92c58482b9e5ccf6981e0559c5cc299a42a1f6f04a461b11a3b8a3014de5"),
			value: mustHex("0100000000000000000000000000000000000000000000000000000000000000"),
		},
		{
			name:  "z40_mixed_batch_packet_commitment",
			key:   mustHex("a27e1b52c3beaeb1c4b3c6afb3bb6000536eb98562c019f0109f7b1274a3d102"),
			value: mustHex("0100000000000000000000000000000000000000000000000000000000000000"),
		},
		{
			name:  "z40_panic_batch_packet_commitment",
			key:   mustHex("9102811e2a4d94c7593e8711e65c4163820045992a2ab08e771615a067ca23cd"),
			value: mustHex("0100000000000000000000000000000000000000000000000000000000000000"),
		},
	}
	for _, fx := range makeFixtureSet(baseFixtures) {
		printFixture(fx)
	}
	for _, fx := range makeFixtureSet(z35Fixtures) {
		printFixture(fx)
	}
	// Receipt and ack share PacketAcknowledgementPath under the Union spec,
	// so z37's non-membership target collides with z36's ack key inside one
	// fixture set. Generate z37 in its own set, but include the connection
	// and channel try entries so scenarios can open a channel on the same
	// client/consensus state used to verify the timeout non-membership.
	z37Fixtures := []fixtureInput{
		{
			name:  "z37_connection_try",
			key:   mustHex("05f3c8eef62e74b10b7ee910fcc73c8358000f692d9ce2341a989e008e45b35d"),
			value: mustHex("ff4fb67348c16e70c898c7cf43c460a684bc900d2b41e5a24ef6dcb294586034"),
		},
		{
			name:  "z37_channel_try",
			key:   mustHex("88601476d11616a71c5be67555bd1dff4b1cbf21533d2669b768b61518cfe1c3"),
			value: mustHex("fa3c11d224a164cd0beca2b6756128dc1531714a75813e9c2b5840bd8f2a8347"),
		},
		{
			name:             "z37_receipt_non_membership",
			key:              []byte("z37-neighbor-anchor"),
			value:            []byte("z37-neighbor-value"),
			nonMembershipKey: mustHex("3cde3b6891df12ae3a04f23e62738b1c7e209ddb5a5dd6ebc27b6c29cd539b18"),
		},
	}
	for _, fx := range makeFixtureSet(z37Fixtures) {
		printFixture(fx)
	}
	z42WrongVersionFixtures := []fixtureInput{
		{
			name:  "z42_wrong_version_connection_try",
			key:   mustHex("05f3c8eef62e74b10b7ee910fcc73c8358000f692d9ce2341a989e008e45b35d"),
			value: mustHex("ff4fb67348c16e70c898c7cf43c460a684bc900d2b41e5a24ef6dcb294586034"),
		},
		{
			name:  "z42_wrong_version_channel_try",
			key:   mustHex("88601476d11616a71c5be67555bd1dff4b1cbf21533d2669b768b61518cfe1c3"),
			value: mustHex("cd241e37da32c69a48f490b088006f8e4b664e2dd28a079730fa9e47c5fd943d"),
		},
	}
	z42StaleFixtures := []fixtureInput{
		{
			name:  "z42_stale_connection_try",
			key:   mustHex("05f3c8eef62e74b10b7ee910fcc73c8358000f692d9ce2341a989e008e45b35d"),
			value: mustHex("ff4fb67348c16e70c898c7cf43c460a684bc900d2b41e5a24ef6dcb294586034"),
		},
		{
			name:  "z42_stale_channel_try",
			key:   mustHex("88601476d11616a71c5be67555bd1dff4b1cbf21533d2669b768b61518cfe1c3"),
			value: mustHex("71eac86d6ae84d0093ae6a570909eb39ab5ee69ffc7ebb213e436fc9ddf24958"),
		},
	}
	for _, fx := range makeFixtureSet(z42WrongVersionFixtures) {
		printFixture(fx)
	}
	for _, fx := range makeFixtureSet(z42StaleFixtures) {
		printFixture(fx)
	}
}

func makeFixtureSet(inputs []fixtureInput) []fixture {
	storeKey := []byte(ibcStoreKey)

	iavlLeaf := encodeLeafOp(
		hashOpSHA256,
		hashOpNoHash,
		hashOpSHA256,
		lengthOpVarProto,
		iavlLeafPrefix(),
	)

	leaves := make([]*iavlLeafNode, 0, len(inputs))
	for i, input := range inputs {
		leaves = append(leaves, &iavlLeafNode{
			input:    input,
			inputIdx: i,
			hash:     applyLeaf(iavlLeafPrefix(), input.key, input.value),
		})
	}
	sort.Slice(leaves, func(i, j int) bool {
		return bytes.Compare(leaves[i].input.key, leaves[j].input.key) < 0
	})
	iavlRoot := buildIavlRoot(leaves).hash

	tmLeaf := encodeLeafOp(
		hashOpSHA256,
		hashOpNoHash,
		hashOpSHA256,
		lengthOpVarProto,
		[]byte{0x00},
	)
	tmExist := encodeExistenceProof(storeKey, iavlRoot, tmLeaf, nil)
	appRoot := applyLeaf([]byte{0x00}, storeKey, iavlRoot)

	out := make([]fixture, len(leaves))
	for _, leaf := range leaves {
		iavlExist := encodeIavlExistenceProof(iavlLeaf, leaf)
		proof := encodeMerkleProof(
			encodeCommitmentExist(iavlExist),
			encodeCommitmentExist(tmExist),
		)

		var nonMembershipProof []byte
		if len(leaf.input.nonMembershipKey) > 0 {
			left, right := nonMembershipNeighbors(leaves, leaf.input.nonMembershipKey, iavlLeaf)
			iavlNonexist := encodeNonExistenceProof(leaf.input.nonMembershipKey, left, right)
			nonMembershipProof = encodeMerkleProof(
				encodeCommitmentNonexist(iavlNonexist),
				encodeCommitmentExist(tmExist),
			)
		}

		out[leaf.inputIdx] = fixture{
			input:              leaf.input,
			subroot:            iavlRoot,
			appRoot:            appRoot,
			proofBz:            proof,
			nonMembershipProof: nonMembershipProof,
		}
	}
	return out
}

func encodeIavlExistenceProof(iavlLeaf []byte, leaf *iavlLeafNode) []byte {
	return encodeExistenceProof(leaf.input.key, leaf.input.value, iavlLeaf, leaf.proof)
}

func nonMembershipNeighbors(leaves []*iavlLeafNode, key []byte, iavlLeaf []byte) (left, right []byte) {
	for _, leaf := range leaves {
		cmp := bytes.Compare(leaf.input.key, key)
		if cmp < 0 {
			left = encodeIavlExistenceProof(iavlLeaf, leaf)
			continue
		}
		if cmp > 0 {
			right = encodeIavlExistenceProof(iavlLeaf, leaf)
			return left, right
		}
		panic(fmt.Sprintf("non-membership key %q exists in fixture set", key))
	}
	return left, nil
}

func buildIavlRoot(leaves []*iavlLeafNode) *iavlNode {
	nodes := make([]*iavlNode, 0, len(leaves))
	for _, leaf := range leaves {
		nodes = append(nodes, &iavlNode{
			hash:   leaf.hash,
			height: 0,
			size:   1,
			leaves: []*iavlLeafNode{leaf},
		})
	}

	for len(nodes) > 1 {
		next := make([]*iavlNode, 0, (len(nodes)+1)/2)
		for i := 0; i < len(nodes); i += 2 {
			if i+1 == len(nodes) {
				next = append(next, nodes[i])
				continue
			}
			next = append(next, combineIavlNodes(nodes[i], nodes[i+1]))
		}
		nodes = next
	}
	return nodes[0]
}

func combineIavlNodes(left, right *iavlNode) *iavlNode {
	height := max(left.height, right.height) + 1
	size := left.size + right.size
	prefix := iavlInnerPrefix(height, size)
	hash := applyInner(prefix, left.hash, right.hash)

	// InnerOp prefix/suffix split: the child hash being substituted goes in
	// between, so leftOp's prefix ends at "len(left)" and suffix carries the
	// length-prefixed right sibling; rightOp's prefix consumes the full left
	// sibling and ends at "len(right)" with an empty suffix.
	leftOpPrefix := concat(prefix, pbVarint(uint64(len(left.hash))))
	rightOpPrefix := concat(prefix, withLength(left.hash), pbVarint(uint64(len(right.hash))))
	leftOp := encodeInnerOp(hashOpSHA256, leftOpPrefix, withLength(right.hash))
	rightOp := encodeInnerOp(hashOpSHA256, rightOpPrefix, nil)
	for _, leaf := range left.leaves {
		leaf.proof = append(leaf.proof, leftOp)
	}
	for _, leaf := range right.leaves {
		leaf.proof = append(leaf.proof, rightOp)
	}

	combinedLeaves := append([]*iavlLeafNode{}, left.leaves...)
	combinedLeaves = append(combinedLeaves, right.leaves...)
	return &iavlNode{
		hash:   hash,
		height: height,
		size:   size,
		leaves: combinedLeaves,
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
	if len(f.nonMembershipProof) > 0 {
		fmt.Printf("non_membership_key: %q\n", f.input.nonMembershipKey)
		fmt.Printf("non_membership_proof: 0x%s\n", hex.EncodeToString(f.nonMembershipProof))
	}
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

func applyInner(prefix, left, right []byte) []byte {
	preimage := append([]byte{}, prefix...)
	preimage = append(preimage, withLength(left)...)
	preimage = append(preimage, withLength(right)...)
	root := sha256.Sum256(preimage)
	return root[:]
}

func withLength(in []byte) []byte {
	out := pbVarint(uint64(len(in)))
	return append(out, in...)
}

func concat(parts ...[]byte) []byte {
	n := 0
	for _, p := range parts {
		n += len(p)
	}
	out := make([]byte, 0, n)
	for _, p := range parts {
		out = append(out, p...)
	}
	return out
}

func iavlLeafPrefix() []byte {
	return iavlInnerPrefix(0, 1)
}

func iavlInnerPrefix(height, size int64) []byte {
	var out []byte
	out = binary.AppendVarint(out, height)
	out = binary.AppendVarint(out, size)
	out = binary.AppendVarint(out, 1) // version
	return out
}

func pbVarint(v uint64) []byte {
	return binary.AppendUvarint(nil, v)
}

func mustHex(s string) []byte {
	bz, err := hex.DecodeString(s)
	if err != nil {
		panic(err)
	}
	return bz
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

func encodeInnerOp(hash uint64, prefix, suffix []byte) []byte {
	var out []byte
	out = append(out, pbVarintField(1, hash)...)
	out = append(out, pbBytesField(2, prefix)...)
	if len(suffix) > 0 {
		out = append(out, pbBytesField(3, suffix)...)
	}
	return out
}

func encodeNonExistenceProof(key, left, right []byte) []byte {
	var out []byte
	if len(key) > 0 {
		out = append(out, pbBytesField(1, key)...)
	}
	if len(left) > 0 {
		out = append(out, pbBytesField(2, left)...)
	}
	if len(right) > 0 {
		out = append(out, pbBytesField(3, right)...)
	}
	return out
}

func encodeCommitmentExist(epBytes []byte) []byte {
	return pbBytesField(1, epBytes)
}

func encodeCommitmentNonexist(nepBytes []byte) []byte {
	return pbBytesField(2, nepBytes)
}

func encodeMerkleProof(proofs ...[]byte) []byte {
	var out []byte
	for _, proof := range proofs {
		out = append(out, pbBytesField(1, proof)...)
	}
	return out
}
