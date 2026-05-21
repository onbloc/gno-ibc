# Sepolia Union ugnot fixtures

These files snapshot observed Union Sepolia outputs for the wrapped `ugnot`
ERC-20 at `0x4271eb8f0243f1e1f303912841fdce55c06cf223`.

The committed fixtures are offline regression inputs. Tests must not call
Sepolia, Etherscan, or Union services. Validate them offline with:

```sh
tools/eth-gno-smoke/fixture.sh sepolia-ugnot --check
```

To refresh them explicitly:

```sh
SEPOLIA_RPC_URL=https://ethereum-sepolia.publicnode.com \
  tools/eth-gno-smoke/fixture.sh sepolia-ugnot --refresh
```

Files:

- `ugnot-token-transfers.json`: normalized ERC-20 `Transfer` logs for the
  observed mint, mint, and burn sequence.
- `ugnot-burn-tx.json`: raw `eth_getTransactionByHash` response for the burn tx.
- `ugnot-burn-receipt.json`: raw `eth_getTransactionReceipt` response for the
  burn tx, including the raw Union/ZKGM-looking event.

The raw event with topic
`0x635b5d234fe7abddfb29b6c8498780a3175c9002c537f20a3d1bf9d0e625b5fe`
is intentionally preserved without assigning a canonical event name yet.
