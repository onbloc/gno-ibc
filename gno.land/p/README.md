# Packages

Stateless gno libraries (`p/`). Importable from any realm or package; no on-chain state of their own.

## Layout

| Namespace | Origin | Notes |
|---|---|---|
| `aib/` | mirrored from `third_party/gno-realms` (`p/aib/...`) | encoding/merkle/ics23 helpers and IBC primitives (app, host, lightclient, types) |
| `core/` | first-party | ABI codec (`encoding/abi`), IBC protobuf, ZKGM ABI types, CometBLS / Tendermint light-client primitives |
| `demo/` | mirrored from `third_party/gnolang-gno` | `tokens/grc20` reference token |
| `gnoswap/` | mirrored from `third_party/gnoswap` | `uint256` arithmetic used by ZKGM and CometBLS |
| `moul/` | mirrored from `third_party/gnolang-gno` | `md` (markdown helpers) |
| `nt/` | mirrored from `third_party/gnolang-gno` | nt stdlib subset: `avl`, `bptree`, `cford32`, `fqname`, `mux`, `seqid`, `testutils`, `uassert`, `ufmt` |
| `onbloc/` | mirrored from `third_party/gnolang-gno` | `diff`, `json` |

Mirrored namespaces are populated by `make vendor`; only the submodule pin is committed. See `third_party/README.md` for the workflow.
