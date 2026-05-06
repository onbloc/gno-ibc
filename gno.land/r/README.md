# Realms

Stateful gno contracts (`r/`). Each subdirectory is a deployable realm with its own persistent storage.

## Layout

| Namespace | Origin | Notes |
|---|---|---|
| `aib/` | mirrored from `third_party/gno-realms` | `ibc/core` — IBC core realm (channels, clients, packets) consumed by ZKGM |
| `core/` | first-party | `ibc/apps/zkgm/` — ZKGM proxy, `v0/impl/` implementation, `v0/loader/`, `testing/mock/` mock receiver. Also `ibc/lightclients/` host wrappers |
| `demo/` | mirrored from `third_party/gnolang-gno` | `defi/grc20reg` global GRC20 registry used by ZKGM voucher tokens |

Mirrored namespaces are populated by `make vendor`; only the submodule pin is committed. See `third_party/README.md` for the workflow.
