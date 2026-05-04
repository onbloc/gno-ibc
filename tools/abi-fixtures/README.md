# abi-fixtures

A small Rust tool that emits canonical Solidity ABI encodings for every ZKGM struct, used as ground-truth for the gno `encoding/abi` codec tests.

## Why

The gno ABI codec must produce byte-identical output to Union's Rust implementation. Hand-rolling test vectors is error-prone. This tool reuses Union's `sol!` macro definitions verbatim and lets `alloy-sol-types` produce the encoded bytes. The gno tests then assert their own encoder/decoder agrees byte-for-byte with the JSON output here.

## Wire flavor: `abi_encode_params` (not `abi_encode`)

Union encodes ZKGM wire bytes via `abi_encode_params` and decodes via `abi_decode_params_validate` — see `cosmwasm/app/ucs03-zkgm/src/contract.rs:270, 556, 578` and similar. The `_params` flavor treats the struct's fields as a top-level tuple. The plain `abi_encode` (without `_params`) prepends an extra 32-byte `head_offset(0x20)` because it treats the struct as a single dynamic value passed as a function argument.

The two forms differ by exactly 32 bytes at the very start. **All vectors here, and the gno encoder/decoder, must use the `_params` flavor.** A first version of this harness used plain `abi_encode` and the `RealPacket_msg_rs_259` round-trip caught the mismatch — keep that fixture in place to lock the convention in.

## Output schema

`vectors.json` is a JSON array. Each entry:

```json
{
  "name": "TokenOrderV2_escrow_basic",
  "type": "TokenOrderV2",
  "fields": { ... },
  "abi_hex": "0x000000…0000"
}
```

Field encoding conventions inside `fields`:

| Solidity type | JSON form |
|---|---|
| `uint8`, `uint64` | JSON number |
| `uint256` | decimal string (avoids JSON number precision loss) |
| `bool` | `true` / `false` |
| `bytes` | hex string with `0x` prefix |
| `bytes32` | hex string with `0x` prefix |
| `string` | JSON string |
| `T[]` | JSON array of element forms |
| nested struct | nested JSON object using the conventions above |

## Regenerating

From the repo root:

```bash
make refresh-abi-vectors
```

This runs `cargo run --release -p abi-fixtures`, captures stdout, and writes the result to a single canonical fixture next to the gno tests that consume it:

- `gno.land/p/core/encoding/abi/testdata/vectors.json`

The `abi-fixtures` CI workflow re-runs this generator on every PR that touches the harness or the committed vectors and asserts the result matches what's checked in — editing `src/main.rs` without committing the regenerated `vectors.json` fails CI. Drift between the committed bytes and the gno encoder/decoder is independently caught by the gno test suite.

## Adding a scenario

1. Open `src/main.rs`, find the matching struct section, append a new block constructing the value.
2. Wrap with `vector("name", "type", json!({...}), &v)` and push into `out`.
3. Pick a `name` that's stable (it ends up in gno test failure output) and unique.
4. Run `make refresh-abi-vectors` and commit both the updated `main.rs` and the regenerated `vectors.json` files.

Cover at least: zero-length bytes, exactly-32-byte bytes (boundary), bytes of length 33 (one full word + one byte of padding), empty arrays, multi-element arrays, deeply nested structs.

## Toolchain

Requires a stable Rust toolchain (`rustup default stable` is enough). No special features used. Only the `cargo run` step is needed; this directory is not part of the gno workspace.
