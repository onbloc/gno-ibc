# Vendored from gnoswap

The `uint256/` directory under this path is a **vendored copy** of the `gnoswap/uint256` package, included here so the gno toolchain can resolve `gno.land/p/gnoswap/uint256` from this workspace without needing a registry or chain pull.

## Source

- Upstream repo: <https://github.com/gnoswap-labs/gnoswap>
- Vendored from commit: `d7207060 fix(uint256): align Lsh truncation safety (#1272)` (2026-04-27)

## Why vendor (not symlink)

The gno toolchain does not follow filesystem symlinks for workspace package discovery — `gno test ./...` against a symlinked path falls back to the gno mod cache and fails with `package "..." is not available`. A real directory copy resolves correctly. (Stdlib packages under `stdlibs/` *are* symlinked into the gno cache, but those are loaded via `_GNOROOT` at runtime and not via workspace discovery.)

## Updating

When the upstream `gnoswap/uint256` package gets a fix or new feature this repo wants to consume:

```bash
# from the repo root, with the gnoswap repo cloned somewhere reachable
rm -rf gno.land/p/gnoswap/uint256
cp -R <path-to-gnoswap-checkout>/contract/p/gnoswap/uint256 \
      gno.land/p/gnoswap/uint256
# update the commit hash above in this file
gno test ./gno.land/p/core/_smoke/   # verify
```

If `gnoswap/uint256` becomes resolvable as a remote chain package later, drop the vendored copy in favor of regular import resolution.

## What depends on this

- `gno.land/p/gnoswap/_smoke` (env-prep smoke test) — delete after Wave 0
- ZKGM port — `p/gnoswap/tokenbucket`, `p/gnoswap/ibc/zkgm/*`, `r/gnoswap/ibc/apps/zkgm/*`
- CometBLS light client — `p/gnoswap/ibc/lightclient/cometbls/`
