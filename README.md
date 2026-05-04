# gno-ibc

Gno ↔ Union integration. CometBLS light client and UCS03 ZKGM contract ported to Gno realms.

<!-- TODO: Update README -->

## Dependencies

### Toolchain

This repo requires a `gno` binary built from upstream `gnolang/gno` (commit pinned in [`.gno-version`](.gno-version)) **plus** a set of native stdlib packages vendored under [`stdlibs/`](stdlibs/). A stock release build will not resolve them.

`make install-gno` runs [`tools/setup-stdlibs.py`](tools/setup-stdlibs.py), which clones the pinned commit into `~/.cache/gno-ibc/gno`, symlinks every `stdlibs/<path>/` into `<cache>/gnovm/stdlibs/<path>/`, regenerates the native-binding dispatch table (`go generate ./stdlibs/...`), and installs the resulting binary.

```bash
make install-gno    # clone + vendor + regenerate + go install
make verify-gno     # assert the gno on PATH matches the pin
```

Make sure `$(go env GOPATH)/bin` is on your `PATH` so the freshly installed `gno` is picked up.

To roll the toolchain forward, edit `.gno-version` and re-run `make install-gno`. To edit a vendored stdlib, change files under `stdlibs/` and re-run `make install-gno`.

### Vendored stdlib packages

Source of truth lives under [`stdlibs/`](stdlibs/). Each package's `gnomod.toml` declares its `module = "crypto/<name>"` path; the setup script symlinks it into the gno cache at the matching location.

| Package | Purpose |
|---|---|
| `crypto/bn254` | BN254 curve arithmetic (EIP-196/197 layout) |
| `crypto/cometbls` | CometBLS Groth16 verifier (native-heavy) |
| `crypto/cometblszk` | Same public API, gno-heavy implementation |
| `crypto/keccak256` | Ethereum Keccak-256 |
| `crypto/modexp` | EIP-198 modular exponentiation |

### Workspace packages

| Import path | Location | Source |
|---|---|---|
| `gno.land/p/gnoswap/uint256` | `gno.land/p/gnoswap/uint256/` | Vendored from upstream `gnoswap`. See [`gno.land/p/gnoswap/VENDORED.md`](gno.land/p/gnoswap/VENDORED.md) for the pinned commit and refresh procedure |

## Environment check

```bash
gno test ./gno.land/p/aib/_smoke/ -v
```

Expected — 4 PASS:
- `TestStdlibSizes` — sanity-checks key constants (Keccak `Size`=32, LightHeader=116 bytes, BN254 `G1AddInputSize`=128, etc.)
- `TestKeccakEmpty` — `keccak256("") == c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470`
- `TestModExpSmall` — `modexp(2, 1, 5) == 2`
- `TestUint256Add` — `uint256.Add(1, 2) == 3`

The `_smoke` package exists only to validate the environment. Delete it once Wave 0 is in.

## Test fixtures

The Solidity ABI codec at `gno.land/p/aib/encoding/abi/` is tested against ground-truth byte sequences produced by Union's own `sol!` macro definitions. See [`tools/abi-fixtures/`](tools/abi-fixtures/) for the Rust harness; gno tests read its output from `gno.land/p/aib/encoding/abi/testdata/vectors.json`.

```bash
make refresh-abi-vectors    # regenerate vectors.json after editing the harness
```

ZKGM wire bytes follow the `abi_encode_params` flavor (no top-level head-offset prefix), not plain `abi_encode`. Both the harness and the gno codec must use this flavor — see the harness README for details.

## Toolchain gotchas

Non-obvious behaviors observed while wiring up the workspace:

### 1. Symbolic links are not followed (workspace packages only)
If a package under the workspace is a symlink, `gno test` falls through to the mod cache and fails:

```text
gno: downloading gno.land/p/.../...
... package "gno.land/p/.../..." is not available
```

**Use real directory copies** (`cp -R`) when bringing in packages from sibling repos. No symlinks for workspace packages. (Stdlib packages under `stdlibs/` *are* symlinked into the gno cache by [`tools/setup-stdlibs.py`](tools/setup-stdlibs.py), but those are loaded via `_GNOROOT` at runtime — separate code path.)

### 2. `gnowork.toml` is just a marker
An empty file works. Its job is to mark the workspace root, not to enumerate members. Member packages are auto-discovered — any directory containing a `gnomod.toml` is a package.

### 3. Package resolution order
When `gno test` resolves an import like `gno.land/p/x`:
1. **Workspace local** — walk up to the nearest `gnowork.toml`, then look for `gno.land/p/x/gnomod.toml` underneath.
2. **Mod cache** — the `gno/pkg/mod/gno.land/p/x/` directory under your platform's user data dir.
3. **Remote download** — try fetching from the gno.land chain.

External packages that are neither in the workspace nor in the mod cache (e.g. `gnoswap/uint256`) trigger a download attempt and fail. **They must be vendored or pre-populated in the mod cache.**

### 4. Vendored packages do not auto-update
A vendored copy (e.g. `gno.land/p/gnoswap/uint256`) does not track upstream changes. To refresh, follow the procedure in [`gno.land/p/gnoswap/VENDORED.md`](gno.land/p/gnoswap/VENDORED.md).

### 5. No `go tool gno` here
This repo has no `go.mod` and does not pin the fork via a Go module `replace` directive. The pin is a commit SHA in [`.gno-version`](.gno-version), and the `gno` binary is installed by `make install-gno`. Test invocations go through `make`:

```bash
make test          # verify-gno, then `gno test ./gno.land/...`
make test-stdlibs  # vendored stdlib's own .gno + .go tests
make test-smoke    # only the env-prep smoke tests
```

`make verify-gno` (also run as a prerequisite of `make test`) checks the `gno` on `PATH` matches the pinned commit and tells you to re-run `make install-gno` if not.
