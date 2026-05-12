// gen-ethereum-storage-proof-fixture emits a deterministic Ethereum storage
// trie proof fixture for the Gno storage verifier tests.
//
// It uses go-ethereum's trie.Prove API, following the pattern in:
// https://github.com/ethereum/go-ethereum/blob/master/trie/proof_test.go
package main

import (
	"bytes"
	"encoding/hex"
	"fmt"
	"sort"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/ethereum/go-ethereum/ethdb/memorydb"
	"github.com/ethereum/go-ethereum/rlp"
	"github.com/ethereum/go-ethereum/trie"
)

type proofNode struct {
	hash common.Hash
	rlp  []byte
}

func main() {
	tr, err := trie.New(common.Hash{}, common.Hash{}, trie.NewDatabase(memorydb.New()))
	if err != nil {
		panic(err)
	}

	slots := [][]byte{
		wordFromUint64(1),
		wordFromUint64(2),
		wordFromUint64(3),
	}
	values := [][]byte{
		mustRLPEncodeUint64(0x1234),
		mustRLPEncodeUint64(0xdeadbeef),
		mustRLPEncodeUint64(0x80),
	}
	for i := range slots {
		tr.Update(crypto.Keccak256(slots[i]), values[i])
	}

	root := tr.Hash()
	fmt.Printf("root: %s\n", root.Hex())
	for i := range slots {
		fmt.Printf("slot%d: 0x%s\n", i+1, hex.EncodeToString(slots[i]))
		fmt.Printf("path%d: 0x%s\n", i+1, hex.EncodeToString(crypto.Keccak256(slots[i])))
		fmt.Printf("leafPayload%d: 0x%s\n", i+1, hex.EncodeToString(values[i]))
	}
	fmt.Println()

	existenceProof := memorydb.New()
	if err := tr.Prove(crypto.Keccak256(slots[1]), 0, existenceProof); err != nil {
		panic(err)
	}
	fmt.Printf("existenceKey: 0x%s\n", hex.EncodeToString(slots[1]))
	fmt.Printf("existenceValue: 0x%s\n", hex.EncodeToString(wordFromUint64(0xdeadbeef)))
	printProof("existenceProof", root, existenceProof)
	fmt.Println()

	missingSlot := wordFromUint64(4)
	absenceProof := memorydb.New()
	if err := tr.Prove(crypto.Keccak256(missingSlot), 0, absenceProof); err != nil {
		panic(err)
	}
	fmt.Printf("absenceKey: 0x%s\n", hex.EncodeToString(missingSlot))
	fmt.Printf("absencePath: 0x%s\n", hex.EncodeToString(crypto.Keccak256(missingSlot)))
	printProof("absenceProof", root, absenceProof)
	fmt.Println()

	ibcPath := bytes.Repeat([]byte{0x11}, 32)
	fmt.Printf("ibcPath: 0x%s\n", hex.EncodeToString(ibcPath))
	fmt.Printf("ibcCommitmentKey: 0x%s\n", hex.EncodeToString(ibcCommitmentKey(ibcPath)))
	fmt.Printf("ibcZeroPathCommitmentKey: 0x%s\n", hex.EncodeToString(ibcCommitmentKey(make([]byte, 32))))
}

func printProof(name string, root common.Hash, db *memorydb.Database) {
	nodes := collectNodes(db)
	ordered := orderProof(root, nodes)
	fmt.Printf("%sNodes: %d\n", name, len(ordered))
	for i, node := range ordered {
		fmt.Printf("%s[%d]: 0x%s\n", name, i, hex.EncodeToString(node))
	}
}

func collectNodes(db *memorydb.Database) map[common.Hash][]byte {
	out := make(map[common.Hash][]byte)
	it := db.NewIterator(nil, nil)
	defer it.Release()
	for it.Next() {
		out[common.BytesToHash(copyBytes(it.Key()))] = copyBytes(it.Value())
	}
	return out
}

func orderProof(root common.Hash, nodes map[common.Hash][]byte) [][]byte {
	var ordered [][]byte
	seen := make(map[common.Hash]bool)
	next := root
	for {
		node, ok := nodes[next]
		if !ok {
			break
		}
		if seen[next] {
			panic("proof cycle")
		}
		seen[next] = true
		ordered = append(ordered, node)

		child, ok := nextHashedChild(node, nodes, seen)
		if !ok {
			break
		}
		next = child
	}
	if len(ordered) != len(nodes) {
		panic(fmt.Sprintf("ordered %d nodes, proof db has %d", len(ordered), len(nodes)))
	}
	return ordered
}

func nextHashedChild(encoded []byte, nodes map[common.Hash][]byte, seen map[common.Hash]bool) (common.Hash, bool) {
	var list []rlp.RawValue
	if err := rlp.DecodeBytes(encoded, &list); err != nil {
		panic(err)
	}

	var refs []common.Hash
	switch len(list) {
	case 17:
		for i := 0; i < 16; i++ {
			if len(list[i]) == 33 && list[i][0] == 0xa0 {
				refs = append(refs, common.BytesToHash(list[i][1:]))
			}
		}
	case 2:
		if len(list[1]) == 33 && list[1][0] == 0xa0 {
			refs = append(refs, common.BytesToHash(list[1][1:]))
		}
	default:
		panic(fmt.Sprintf("unexpected node shape: %d", len(list)))
	}

	var candidates []common.Hash
	for _, ref := range refs {
		if _, ok := nodes[ref]; ok && !seen[ref] {
			candidates = append(candidates, ref)
		}
	}
	sort.Slice(candidates, func(i, j int) bool {
		return bytes.Compare(candidates[i][:], candidates[j][:]) < 0
	})
	if len(candidates) == 0 {
		return common.Hash{}, false
	}
	if len(candidates) > 1 {
		panic("ambiguous proof path")
	}
	return candidates[0], true
}

func wordFromUint64(v uint64) []byte {
	out := make([]byte, 32)
	for i := 31; i >= 24; i-- {
		out[i] = byte(v)
		v >>= 8
	}
	return out
}

func mustRLPEncodeUint64(v uint64) []byte {
	out, err := rlp.EncodeToBytes(v)
	if err != nil {
		panic(err)
	}
	return out
}

func ibcCommitmentKey(path []byte) []byte {
	if len(path) != 32 {
		panic("path must be 32 bytes")
	}
	var input [64]byte
	copy(input[:32], path)
	return crypto.Keccak256(input[:])
}

func copyBytes(b []byte) []byte {
	out := make([]byte, len(b))
	copy(out, b)
	return out
}
