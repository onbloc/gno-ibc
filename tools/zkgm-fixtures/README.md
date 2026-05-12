# zkgm-fixtures

A small Rust tool that emits canonical handler/dispatch end-to-end **scenario** fixtures for the gno ZKGM tests. Each scenario is a full `ZkgmPacket` envelope (salt + path + one of the four opcodes) paired with the canonical success/failure `Ack` envelope that the handler should emit on the happy path.

## Why

`abi-fixtures` pins per-struct encoding correctness for each ZKGM body in isolation. `zkgm-fixtures` complements that by pinning the full **envelope** shape and the **packet + ack pairing** — i.e. exactly what arrives on the IBC wire and exactly what should go back. The gno handler/dispatch tests build the same `ZkgmPacket` via in-tree types, encode it, and assert byte-equality with `packet_data_hex`; they also build the matching success/failure `Ack` and assert byte-equality with `success_ack_hex` / `failure_ack_hex`.

State-dependent handler effects (voucher mints, channel-balance updates, rate-limit buckets, event emission) stay in pure gno handler tests because they require gno-side state. The scenarios pin only what's wire-determined.

## Wire flavor: `abi_encode_params`

Same convention as `abi-fixtures` — Union encodes ZKGM wire bytes via `abi_encode_params` / decodes via `abi_decode_params_validate`. Every gno encoder/decoder uses this flavor, and every byte string emitted here is produced via `abi_encode_params`. See `tools/abi-fixtures/README.md` for the full reasoning.

## Output schema

`scenarios.json` is a JSON array. Each entry:

```json
{
  "name": "recv_token_order_v2_initialize_protocol_fill",
  "instruction_type": "TokenOrderV2",
  "source_channel": 1,
  "destination_channel": 5,
  "packet": {
    "salt": "0x33…33",
    "path": "7",
    "instruction": { "version": 2, "opcode": 3, "operand": "0x…" }
  },
  "decoded": { /* inner instruction fields */ },
  "packet_data_hex": "0x…",
  "success_ack_hex": "0x…",
  "failure_ack_hex": "0x…"
}
```

Field encoding conventions inside `decoded` and `packet` follow the same rules as the `abi-fixtures` README:

| Solidity type | JSON form |
|---|---|
| `uint8`, `uint64` | JSON number |
| `uint256` | decimal string |
| `bool` | `true` / `false` |
| `bytes`, `bytes32` | hex string with `0x` prefix |
| `string` | JSON string |
| `T[]` | JSON array of element forms |
| nested struct | nested JSON object |

The canonical success ack for each opcode:

| Opcode | Success inner ack |
|---|---|
| `OP_CALL` | empty bytes (`0x`) |
| `OP_TOKEN_ORDER` (escrow / unescrow / initialize) | `TokenOrderAck{FILL_TYPE_PROTOCOL, market_maker=0x}` |
| `OP_TOKEN_ORDER` (solve) | `TokenOrderAck{FILL_TYPE_MARKETMAKER, market_maker=<addr>}` |
| `OP_BATCH` | `BatchAck` of the per-sub-instruction inner acks |
| `OP_FORWARD` | inner hop's inner ack (capped at one level here; deeper recursion is gno-side) |

The canonical failure ack across all scenarios is `Ack{tag=0, inner_ack=b"UNIVERSAL_ERROR"}` — what `dispatch.gno`'s `universalErrorAck()` emits.

## Regenerating

From the repo root:

```bash
make refresh-zkgm-scenarios
```

This runs `cargo run --release -p zkgm-fixtures`, captures stdout, and writes the result to:

- `gno.land/p/core/ibc/zkgm/testdata/scenarios.json` (canonical JSON)
- `gno.land/p/core/ibc/zkgm/scenarios_fixture_test.gno` (raw-string embedding for gno tests, mirroring `vectors_fixture_test.gno`)

The `abi-fixtures` CI workflow should be extended to also re-run this generator on every PR that touches the harness or the committed scenarios and assert the result matches what's checked in.

## Adding a scenario

1. Open `src/main.rs`, find the matching opcode section, append a new block constructing the inner instruction + packet.
2. Wrap with `Scenario { … }` and push into `out`.
3. Pick a `name` that's stable (it ends up in gno test failure output) and unique.
4. Run `make refresh-zkgm-scenarios` and commit both the updated `main.rs` and the regenerated `scenarios.json` + `scenarios_fixture_test.gno` files.

## Replaying scenarios via gnokey

The `scripts/` directory contains a small wrapper that turns each scenario into a `gnokey maketx run` script that invokes `zkgm.Send(...)` with the scenario's `salt`, `instruction`, `source_channel`, and `tx_timeout_timestamp`.

```bash
# Render every scenario into scripts/out/<name>.gno (no execution).
tools/zkgm-fixtures/scripts/gen-send-script.sh --all

# Render a single scenario.
tools/zkgm-fixtures/scripts/gen-send-script.sh recv_call_eureka_true

# Render and execute against a running chain.
GNOKEY_REMOTE=tcp://127.0.0.1:26657 \
GNOKEY_CHAINID=dev \
GNOKEY_KEYNAME=test1 \
tools/zkgm-fixtures/scripts/gen-send-script.sh recv_token_order_v2_escrow_protocol_fill --exec
```

The rendered scripts compile against the published `gno.land/r/core/ibc/v1/apps/zkgm` realm and reuse `gno.land/p/gnoswap/ibc/zkgm` types. Output directory (`scripts/out/`) is gitignored — re-render whenever scenarios are regenerated.

This only covers the **send** side. Replaying the recv/ack side would require a real IBC light-client proof and is out of scope for direct fixture replay; the `gno.land/r/core/ibc/v1/apps/zkgm/testing/e2e/` harness is the right place for that.

## Sync with Union

The `sol!` struct block, opcode constants, fill-type constants, ack-tag constants, and token-order-kind constants are a verbatim copy of `union/cosmwasm/app/ucs03-zkgm/src/com.rs` — the same source `abi-fixtures` keeps in sync. If Union ever changes the wire format, regenerate **both** fixtures.

## Toolchain

Requires a stable Rust toolchain (`rustup default stable`). No special features. This directory is part of the workspace `Cargo.toml` and is not part of the gno workspace.
