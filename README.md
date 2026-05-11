# gno-ibc

Gno ↔ Union integration. CometBLS light client and UCS03 ZKGM contract ported to Gno realms.

## Development

```bash
nix develop          # optional: pinned toolchain (Go, Python+pytest, gofumpt, ...)
make install-gno     # required: build gno with this repo's native stdlibs
```

The flake supplies the supporting toolchain only — the gno binary's keccak256 / bn254 / cometbls native bindings come from `make install-gno`.

## Testing

```bash
make test          # first-party gno tests
make test-stdlibs  # vendored stdlib tests
```
