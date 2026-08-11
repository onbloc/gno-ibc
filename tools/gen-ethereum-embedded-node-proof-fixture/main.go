// gen-ethereum-embedded-node-proof-fixture emits a real go-ethereum MPT proof
// containing embedded (inline) child nodes, for the Gno mpt package's tests.
// See README.md for why real storage proofs can't produce these naturally.
package main

import (
	"encoding/hex"
	"fmt"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/ethdb/memorydb"
	"github.com/ethereum/go-ethereum/rlp"
	"github.com/ethereum/go-ethereum/trie"
)

func main() {
	tr, err := trie.New(common.Hash{}, common.Hash{}, trie.NewDatabase(memorydb.New()))
	if err != nil {
		panic(err)
	}

	// 31-byte shared prefix (62 nibbles); the keys below diverge only in the
	// last byte's high nibble, leaving 2 nibbles for the branch+leaf to split.
	prefix := make([]byte, 31)
	for i := range prefix {
		prefix[i] = 0xAB
	}
	keys := [][]byte{
		append(append([]byte{}, prefix...), 0x10),
		append(append([]byte{}, prefix...), 0x20),
		append(append([]byte{}, prefix...), 0x30),
	}
	values := [][]byte{
		mustRLP(1),
		mustRLP(2),
		mustRLP(3),
	}
	for i := range keys {
		tr.Update(keys[i], values[i])
	}

	root := tr.Hash()
	fmt.Printf("root: %s\n", hex.EncodeToString(root[:]))
	for i := range keys {
		fmt.Printf("key%d: %s\n", i+1, hex.EncodeToString(keys[i]))
		fmt.Printf("value%d: %s\n", i+1, hex.EncodeToString(values[i]))
	}

	// Everything below the root extension is embedded, so the proof has one entry.
	proofDB := memorydb.New()
	if err := tr.Prove(keys[0], 0, proofDB); err != nil {
		panic(err)
	}
	printProofAndVerify("existence", tr, root, keys[0], proofDB)

	missing := append(append([]byte{}, prefix...), 0x40)
	fmt.Printf("missingKey: %s\n", hex.EncodeToString(missing))
	absenceDB := memorydb.New()
	if err := tr.Prove(missing, 0, absenceDB); err != nil {
		panic(err)
	}
	printProofAndVerify("absence", tr, root, missing, absenceDB)
}

func printProofAndVerify(label string, tr *trie.Trie, root common.Hash, key []byte, db *memorydb.Database) {
	it := db.NewIterator(nil, nil)
	defer it.Release()
	n := 0
	for it.Next() {
		fmt.Printf("%sProof[%d]: %s\n", label, n, hex.EncodeToString(common.CopyBytes(it.Value())))
		n++
	}
	if n != 1 {
		panic(fmt.Sprintf("%s: expected exactly 1 proof node (everything else embedded), got %d", label, n))
	}

	// Sanity-check against go-ethereum's own verifier, independent of our
	// node-ordering logic.
	val, err := trie.VerifyProof(root, key, db)
	fmt.Printf("%s geth-verified value: %s (err=%v)\n", label, hex.EncodeToString(val), err)
}

func mustRLP(v uint64) []byte {
	out, err := rlp.EncodeToBytes(v)
	if err != nil {
		panic(err)
	}
	return out
}
