# Realms

Stateful gno contracts (`r/`). Each subdirectory is a deployable realm with its own persistent storage.

## Layout

| Namespace | Origin | Notes |
|---|---|---|
| `aib/` | mirrored from `third_party/gno-realms` | `ibc/core` — IBC core realm (channels, clients, packets) consumed by ZKGM |
| `onbloc/` | first-party | `ibc/union/core/` — Union IBC core; `ibc/union/apps/ucs03_zkgm/` — ZKGM proxy, `v1/` implementation, and test realms |
| `demo/` | mirrored from `third_party/gnolang-gno` | `defi/grc20reg` global GRC20 registry used by ZKGM voucher tokens |

Mirrored namespaces are populated by `make vendor`; only the submodule pin is committed. See `third_party/README.md` for the workflow.
