# Documentation

- [Implementation Specs](specs/README.md) — current implementation specs for IBC core, ZKGM, light clients, and events
- [TX Indexer Guide](tx-indexer.md) — querying IBC transactions and events via the deployed tx-indexer
- [IBC Native Function Gas Table](ibc-native-gas.md) — calibrated gas costs for the IBC / CometBLS native bindings registered in `gnovm/stdlibs/native_gas.go`
- [ZKGM Packet Send Guide](zkgm-packet-send-guide.md) — index for common SendRaw steps and per-kind TokenOrderV2 INITIALIZE / ESCROW procedures

## Local Development

The repository pins a Gno toolchain version and links a temporary local stdlib
overlay so packages can import native bindings that have not yet landed
upstream. Both pieces are operational scaffolding, not part of the IBC spec
surface.

### Toolchain pin

The expected upstream Gno version is pinned in
[`.gno-version`](../.gno-version). The Makefile and
[`tools/setup-stdlibs.py`](../tools/setup-stdlibs.py) use this pin to install a
compatible local `gno`, `gnodev`, and `gnokey`.

### Make targets

| Target | Purpose |
|--------|---------|
| `make install-gno` | Clone the pinned Gno tree, link the local stdlib overlay, inject calibrated native gas rows when supported, regenerate, and install binaries |
| `make link-stdlibs` | Refresh local stdlib overlay links without rebuilding the full toolchain |
| `make verify-gno` | Check that `gno` is on `PATH` and matches the expected setup |
| `make vendor` | Refresh vendored Gno dependencies used by this repository |
| `make test` | Verify the toolchain, vendor dependencies, and run first-party Gno tests |

### Local stdlib overlay

Local stdlibs live under [`stdlibs/`](../stdlibs). They are linked into the
pinned Gno cache so repository packages can import native bindings used by IBC
and ZKGM (BN254, CometBLS, Keccak, Merkle, modular exponentiation). The
overlay is not a permanent public API. It exists to unblock IBC and ZKGM
development while the corresponding bindings are upstreamed to Gno. When
upstream Gno provides them, repository code switches to the upstream imports
and this overlay is removed. The migration is tracked in
[onbloc/gno-ibc#74](https://github.com/onbloc/gno-ibc/issues/74), which depends
on upstream [gnolang/gno#5725](https://github.com/gnolang/gno/pull/5725).

Calibrated native gas rows live in
[`stdlibs/native_gas_calibration.txt`](../stdlibs/native_gas_calibration.txt)
and are injected into the pinned Gno cache by `make install-gno` when the
upstream Gno version exposes `gnovm/stdlibs/native_gas.go`. The calibration
model and per-binding values are documented in
[IBC Native Function Gas Table](ibc-native-gas.md).
