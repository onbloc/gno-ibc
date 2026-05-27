# Native Stdlib Overlay and Toolchain Spec

This document describes the pinned Gno toolchain setup and the temporary local
stdlib overlay used by this repository.

The local `stdlibs/` tree is expected to be removed once the required native
bindings and support packages land upstream in Gno. Until then, it is part of
the local development and CI setup.

## Toolchain Pin

The expected upstream Gno version is pinned in
[.gno-version](../../.gno-version). The Makefile and setup script use this
pin to install a compatible local `gno`, `gnodev`, and `gnokey`.

Primary targets:

| Target | Purpose |
|--------|---------|
| `make install-gno` | Clone the pinned Gno tree, link the temporary local stdlib overlay, inject calibrated native gas rows when supported, regenerate, and install binaries |
| `make link-stdlibs` | Refresh local stdlib overlay links without rebuilding the full toolchain |
| `make verify-gno` | Check that `gno` is on `PATH` and matches the expected setup |
| `make test` | Verify the toolchain, vendor dependencies, and run first-party Gno tests |

The setup implementation lives in
[tools/setup-stdlibs.py](../../tools/setup-stdlibs.py).

## Temporary Local Stdlib Overlay

Local stdlibs live under [stdlibs](../../stdlibs). They are linked into the
pinned Gno cache so repository packages can import native bindings and support
libraries during tests and local development.

This overlay is not intended to be a permanent public API. It exists to unblock
IBC and ZKGM development while the corresponding functionality is upstreamed to
Gno. When upstream Gno provides the required packages and native registrations,
repository code should switch to the upstream imports and this overlay should be
removed.

Native and support surfaces include bindings for cryptographic and proof
verification helpers used by IBC and ZKGM, including BN254, CometBLS, Keccak,
Merkle, and modular exponentiation related functionality. Pure Gno support
packages build on those bindings where appropriate.

## Native Gas Calibration

Calibrated native gas rows are maintained in
[stdlibs/native_gas_calibration.txt](../../stdlibs/native_gas_calibration.txt)
and documented in [docs/ibc-native-gas.md](../ibc-native-gas.md).

When the pinned upstream Gno tree exposes `gnovm/stdlibs/native_gas.go`,
`make install-gno` injects the calibrated rows into the local cached tree before
regeneration. Older pins without that file skip the injection path.

The current calibration model is:

```text
gas = base + slope * input_size / 1024
```

The model is intentionally simple and should be recalibrated when native
binding implementations or upstream VM gas accounting changes.

## Vendoring

`make vendor` refreshes vendored Gno dependencies used by this repository.
Vendored output is not the source of truth for the local stdlib overlay; it
mirrors the dependency state required for tests.

## Maintenance Rules

- Update `.gno-version` and toolchain setup together when moving the upstream
  pin.
- Keep local native binding code, calibration rows, and
  `docs/ibc-native-gas.md` aligned until the bindings move upstream.
- Remove local overlay documentation when the repository no longer links
  `stdlibs/` into the pinned Gno cache.
- Prefer Make targets over ad hoc setup commands so local development and CI
  exercise the same path.

## Upstreaming

The intended end state is that Gno owns these stdlib packages and native
registrations directly. After that migration, this document should be reduced to
the remaining toolchain pin and verification workflow, or removed if it no
longer adds information beyond the Makefile.
