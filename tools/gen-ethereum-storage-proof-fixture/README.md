# gen-ethereum-storage-proof-fixture

Generates the fixed go-ethereum storage proof fixture used by
`gno.land/p/core/ethereum/storage`.

The fixture is built with go-ethereum's `trie.Prove` API, following the proof
construction and verification pattern in:

https://github.com/ethereum/go-ethereum/blob/master/trie/proof_test.go

Usage:

```sh
cd tools/gen-ethereum-storage-proof-fixture
go run .
```
