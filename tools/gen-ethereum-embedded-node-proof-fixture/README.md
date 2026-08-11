# gen-ethereum-embedded-node-proof-fixture

Generates a real go-ethereum MPT proof fixture that contains embedded
(inline, RLP-list-shaped) child node references, used by
`gno.land/p/onbloc/verifier/evm/mpt`'s tests to pin the fix for
[[project_mpt_embedded_node_bug]] against a proof go-ethereum itself produces
and verifies, not hand-rolled RLP.

Real Ethereum storage/account proofs key everything by keccak256(preimage),
so a leaf's remaining path after branch divergence is always long enough
that its RLP encoding exceeds 32 bytes — embedded nodes essentially never
occur in practice for such proofs. To still exercise the embedded-node
decode path against go-ethereum's actual encoder, this fixture inserts keys
directly (bypassing the keccak256(slot) step) so they share a long common
prefix, collapsing the trie into an extension node (hash-referenced) whose
child is an embedded branch, whose children are in turn embedded leaves.

Built with go-ethereum's `trie.Prove` / `trie.VerifyProof`, following the
pattern in:

https://github.com/ethereum/go-ethereum/blob/v1.10.26/trie/proof_test.go#L38-L75

Usage:

```sh
cd tools/gen-ethereum-embedded-node-proof-fixture
go run .
```
