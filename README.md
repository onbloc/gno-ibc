# gno-ibc

Gno ↔ Union integration. CometBLS light client and UCS03 ZKGM contract ported to Gno realms.

## Development

```bash
nix develop          # optional: pinned toolchain (Go, gofumpt, ...)
make install-gno     # required: build gno + gnoland + gnodev + gnokey from the pinned upstream
```

The IBC crypto stdlibs (bn254, cometbls, cometblszk, keccak256, merkle, modexp) ship in the upstream gno toolchain (merged via gnolang/gno#5725) and are not vendored locally.

## Testing

```bash
make test          # first-party gno tests
```

## Documentation

See [docs/](docs/README.md) for operational guides.
