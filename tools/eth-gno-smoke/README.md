# ETH/Gno Packet Smoke Harness

This directory is the local, repo-owned smoke harness for proving packet
compatibility in both directions without depending on Union Voyager internals,
external EVM RPCs, Union deployments, or Union devnets.

For a hands-on execution guide, see [`HANDS_ON.md`](./HANDS_ON.md).

## Entrypoints

Two dispatchers are the only entrypoints. The `Makefile` smoke targets call
them, and they wrap the per-scenario scripts under `scenarios/`.

```sh
smoke.sh gno-to-eth          # Gno ZKGM send -> ETH-consumable packet commitment
smoke.sh eth-to-gno          # ETH storage proof -> Gno core.PacketRecv (error ack)
smoke.sh eth-to-gno-success  # ETH storage proof -> Gno core.PacketRecv (success ack)
smoke.sh all                 # every smoke scenario in order

fixture.sh eth-proof                # local anvil ETH storage proof fixture
fixture.sh sepolia-ugnot --check    # validate committed Sepolia ugnot fixtures (offline)
fixture.sh sepolia-ugnot --refresh  # refetch Sepolia ugnot fixtures (needs SEPOLIA_RPC_URL)
```

## Layout

```text
smoke.sh / fixture.sh   dispatchers, the only entrypoints
lib/                    shell library: env.sh, log.sh, gno.sh, eth.sh
cmd/                    Go helpers: encode-storage-proof, check-sepolia-ugnot-fixtures
scenarios/<name>/       one folder per scenario: run.sh, inputs, committed fixture.json
```

Each scenario owns its inputs, template, and generated `fixture.json`:

- `scenarios/gno-to-eth/` proves that a Gno ZKGM send emits packet metadata and
  a batch packet commitment that an ETH-side relayer can consume.
- `scenarios/eth-proof/` starts local `anvil`, deploys a minimal commitment-map
  contract, writes packet commitments, fetches `eth_getProof`, and encodes Union
  `StorageProof` bytes. The two `eth-to-gno-*` scenarios reuse it.
- `scenarios/eth-to-gno-error/` and `scenarios/eth-to-gno-success/` prove that
  storage commitments in a local `anvil` contract can be proven with
  `eth_getProof`, encoded as Union `StorageProof`, and submitted to Gno
  `core.PacketRecv`.
- `scenarios/sepolia-ugnot/` holds committed Union Sepolia ugnot observations
  and the offline validator behind `fixture.sh sepolia-ugnot`.

## Shared Packet Fields

Both directions use `gno.land/r/core/ibc/v1/core.Packet`:

| Field | Wire meaning |
|---|---|
| `SourceChannelId` | Source IBC channel id as a `uint32`-backed `ChannelId`. |
| `DestinationChannelId` | Destination IBC channel id as a `uint32`-backed `ChannelId`. |
| `Data` | Opaque application packet bytes. ZKGM packets are ABI-encoded instruction bytes. |
| `TimeoutHeight` | Height timeout. Current ZKGM sends normally use `0`. |
| `TimeoutTimestamp` | Nanosecond timestamp timeout. Native `SendRaw` smoke uses a far-future value. |

Single packets are committed as a one-element batch:

```text
packet_hash = core.CommitPacket(packet)
batch_hash  = core.CommitPackets([]core.Packet{packet})
batch_path  = core.BatchPacketsPath(batch_hash)
value       = core.COMMITMENT_MAGIC
```

For one packet, `core.PacketCommitmentPath(packet)` is the same path as
`core.BatchPacketsPath(core.CommitPackets([]core.Packet{packet}))`.

## Gno -> ETH Inputs

The Gno extraction runner is responsible for deriving these values:

| Value | Source |
|---|---|
| Packet fields | `PacketSend` event attributes from `gno.land/r/core/ibc/v1/core`. |
| `packet_hash` | `packet_hash` event attribute, cross-checked with `core.CommitPacket`. |
| `batch_path_hex` | `core.BatchPacketsPath(core.CommitPackets([]core.Packet{packet}))`. |
| `commitment_value_hex` | Query result for the batch packet commitment path; expected `COMMITMENT_MAGIC`. |
| `proof_height` | Block height used for the Gno store proof. |
| `proof` | Store proof for `batch_path_hex` at `proof_height`. |

The tx-indexer query shape for multi-attribute `PacketSend` filtering is
documented in `docs/tx-indexer.md`. Prefer direct RPC store proof extraction
when available; keep the exact query JSON in `scenarios/gno-to-eth/` whenever
the runner depends on GraphQL.

Expected fixture:

```json
{
  "packet": {
    "source_channel_id": 1,
    "destination_channel_id": 2,
    "data_hex": "0x...",
    "timeout_height": "0",
    "timeout_timestamp": "0"
  },
  "packet_hash": "0x...",
  "batch_path_hex": "0x...",
  "commitment_value_hex": "0x...",
  "proof_height": 123,
  "proof": {}
}
```

## ETH -> Gno Inputs

The ETH receive runner is responsible for deriving these values:

| Value | Source |
|---|---|
| Packet fields | Local fixture or ETH-side send transaction input. |
| `batch_hash` | `core.CommitPackets([]core.Packet{packet})`, mirrored by the ETH contract key convention. |
| ETH storage slot | Local minimal commitment-map contract using the same mapping key convention. |
| `storage_root` | ETH block header storage root for the proof block. |
| `proof_height` | Gno state-lens consensus height that stores `storage_root`. |
| `proof_bytes` | Union `ethereum_light_client_types::StorageProof` bytes accepted by `storage.DecodeProof`. |

Submit the proof with:

```gno
core.PacketRecv(cross, core.MsgPacketRecv{
    Packets:     []core.Packet{packet},
    RelayerMsgs: [][]byte{relayerMsg},
    Proof:       proofBytes,
    ProofHeight: proofHeight,
})
```

The receive smoke must assert `PacketRecv` and `WriteAck` events and then
attempt a duplicate receive to lock down current core semantics.

Expected fixture:

```json
{
  "packet": {
    "source_channel_id": 1,
    "destination_channel_id": 2,
    "data_hex": "0x...",
    "timeout_height": "0",
    "timeout_timestamp": "0"
  },
  "eth": {
    "contract": "0x...",
    "commitment_map_slot": "0x...",
    "block_number": "0x...",
    "storage_root": "0x...",
    "storage_slot": "0x..."
  },
  "proof_height": 1,
  "proof_bytes_hex": "0x..."
}
```

## Runner Status

Both directional smoke scenarios are implemented for local coverage.
`scenarios/eth-to-gno-error/run.sh` generates local anvil storage proofs for the
connection ack, channel ack, and packet commitment paths, creates a state-lens
client with the resulting storage root, submits `core.PacketRecv`, checks
`PacketRecv` and `WriteAck` events, and verifies that a duplicate receive leaves
the acknowledgement unchanged.
