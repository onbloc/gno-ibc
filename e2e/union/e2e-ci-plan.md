# Union E2E CI Implementation Plan

## Goal

Run a deterministic Gno -> Union `PacketSend -> PacketRecv -> WriteAck -> PacketAck`
test in CI, using Voyager as the relayer.

The target validated path is:

- Gno chain: `dev`
- Union chain: `union-devnet-1`
- Gno channel: `3`
- Union channel: `2`
- Gno event source: `gno.land/r/onbloc/ibc/union/core`
- ZKGM app: `gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm`

## Current State

Already available:

- Docker Compose services for Gno, tx-indexer, Postgres, and Voyager.
- `packet-watch` CLI for detecting Gno `PacketSend`.
- Go E2E tests in `e2e/union/packet_test.go`.
- `TestGnoToUnionPacketRelay` already:
  - broadcasts `SendRaw`
  - waits for Gno `PacketSend`
  - waits for Gno `PacketAck`

Not CI-ready yet:

- Voyager and Gno images are expensive to build from scratch.
- client / connection / channel setup is not deterministic enough for PR CI.
- stale Union-side Gno clients can fail with:
  `10-gno: new val set cannot be trusted`
- Voyager does not always automatically index the exact Gno/Union blocks needed
  for a short, deterministic test.

## CI Strategy

Use the smallest reliable CI path:

1. Pull prebuilt images.
2. Start local Gno, tx-indexer, Union devnet, Postgres, and Voyager.
3. Restore or create a known open Gno <-> Union channel.
4. Broadcast one Gno `SendRaw`.
5. Explicitly enqueue the exact Gno `PacketSend` block into Voyager.
6. Wait for Union `wasm-write_ack`.
7. Explicitly enqueue the exact Union `write_ack` block into Voyager.
8. Assert Gno `PacketAck` for the same packet hash.

Avoid full from-scratch chain/bootstrap/proof setup in PR CI. Keep that for
nightly or manual jobs.

## Docker Images

Use an official Union Voyager runtime image if Union publishes one with all
required plugins/modules. If no such image is available, build and publish the
local E2E image.

| Image | Source | Purpose |
| --- | --- | --- |
| `gno-ibc-e2e-gno:<sha>` | `e2e/union/gno/Dockerfile` | Gno node with current `gno.land/...` source |
| `union-voyager-build:<sha>` | `e2e/union/voyager-build.Dockerfile` | Fallback Voyager runtime image when no official image fits |

Pull these external images with pinned tags or digests:

| Image | Purpose |
| --- | --- |
| `postgres:16-alpine` | Voyager DB |
| `ghcr.io/gnolang/tx-indexer:<pinned>` | Gno GraphQL event indexer |
| `ghcr.io/unionlabs/union:<pinned>` | Union devnet |

Do not include the legacy `ghcr.io/allinbits/ibc-v2-ts-relayer` in the CI Ack
job. Voyager is the relayer under test.

## Required Test Harness Changes

### 1. Add deterministic block enqueue helpers

Add small Go helpers under `e2e/union`:

- enqueue Gno block:
  `voyager-event-source-plugin-gno/dev fetch_block`
- enqueue Union block:
  `voyager-event-source-plugin-cosmwasm/union-devnet-1 fetch_block`
- query Union `wasm-packet_recv` / `wasm-write_ack` txs by packet hash
- query Voyager `queue stats` and `queue query-failed`

Keep them as `exec.Command` helpers using existing Docker Compose/Voyager CLI.
No new service or abstraction is needed.

### 2. Extend `TestGnoToUnionPacketRelay`

Current flow:

1. `SendRaw`
2. wait `PacketSend`
3. wait `PacketAck`

CI flow should become:

1. capture baseline queue/done/failed IDs
2. `SendRaw`
3. wait `PacketSend`
4. enqueue Gno `PacketSend` block
5. wait Union `wasm-write_ack`
6. enqueue Union `write_ack` block
7. wait Gno `PacketAck`
8. assert no new Voyager failed rows
9. assert new Voyager done rows contain the packet hash

### 3. Add setup validation

Before broadcasting:

- `QueryConnection(<gno-connection-id>)` is non-empty
- `QueryChannel(<gno-channel-id>)` is non-empty
- Voyager `queue query-failed` is `[]`
- tx-indexer GraphQL responds
- Union RPC responds

Use environment variables for IDs:

```sh
GNO_PACKET_CONNECTION_ID=5
GNO_PACKET_CHANNEL_ID=3
UNION_PACKET_CONNECTION_ID=3
UNION_PACKET_CHANNEL_ID=2
UNION_GNO_CLIENT_ID=1
```

### 4. Handle stale Union-side Gno client

Make the test self-healing for the one known local stale-client failure:

1. Try the normal Voyager path first.
2. If Union `packet_recv` fails with
   `10-gno: new val set cannot be trusted`, generate Gno client-state bytes for
   the packet proof height.
3. Broadcast Union `force_update_client` for the existing Union Gno client.
4. Retry `packet_recv` once.

Do not add a manual env flag. The failure string is specific enough to trigger
the recovery automatically.

The Voyager `msg create-client --height <proof-height>` command is only used as
a bytes generator for `client_state_bytes` and `consensus_state_bytes`. It must
not be enqueued and does not create a replacement client. The on-chain recovery
message is Union core `force_update_client` for the existing client id.

## State Setup Options

### Option A: Volume snapshot, target PR CI path

Create a CI artifact containing:

- Gno chain state with:
  - core deployed
  - ZKGM deployed and registered
  - Gno client `1`
  - connection `5`
  - channel `3`
- Union devnet state with:
- Union Gno client `1`
  - connection `3`
  - channel `2`
  - ZKGM contracts deployed

CI restores volumes, starts services, then runs only packet relay assertions.

Pros:

- fastest PR CI path
- least flaky
- avoids repeated handshake/proof work

Cons:

- snapshot refresh process must be documented
- snapshots are coupled to image/source versions

### Option B: Admin recovery setup, first implementation

Start fresh chains and use existing admin/recovery entrypoints to create the
known connection/channel state.

Pros:

- less artifact management
- easier to update while contracts are changing

Cons:

- slower
- more moving parts in PR CI
- still needs Union-side client handling

### Option C: Full handshake through Voyager, nightly only

Let Voyager create clients, connections, and channels from scratch.

Pros:

- highest integration coverage

Cons:

- too slow and flaky for PR CI
- depends on prover availability and light-client update timing

## Proposed Phases

### Phase 1: Confirm image path

Deliverables:

- Check whether an official Union Voyager image contains the required binaries.
- If not, build `union-voyager-build:<sha>`.
- Build `gno-ibc-e2e-gno:<sha>`.
- Make Compose consume image tags from env vars.

Exit criteria:

- Test jobs do not build Voyager from source.
- Test jobs do not build Gno from source unless image cache misses.

### Phase 2: Make current test deterministic locally

Deliverables:

- Use Option B admin recovery setup.
- Add enqueue helpers.
- Extend `TestGnoToUnionPacketRelay`.
- Add `RUN_PACKET_TESTS=1` local command in README.
- Add stale-client auto-retry for the exact trusted-validator error.

Exit criteria:

- A clean local Compose run sends one packet and observes `PacketAck`.
- No new Voyager failed rows.
- New Voyager done rows contain the packet hash.

### Phase 3: Add PR CI packet relay job

Deliverables:

- CI job starts Compose services.
- Setup runs Option B admin recovery.
- Runs:

```sh
RUN_PACKET_TESTS=1 \
GNO_PACKET_CONNECTION_ID=5 \
GNO_PACKET_CHANNEL_ID=3 \
UNION_PACKET_CONNECTION_ID=3 \
UNION_PACKET_CHANNEL_ID=2 \
UNION_GNO_CLIENT_ID=1 \
GNO_PACKET_OPERAND_HEX=<fixture> \
GNO_PACKET_SEND_COINS=1ugnot \
go test -v ./e2e/union -run TestGnoToUnionPacketRelay
```

Exit criteria:

- PR CI validates `PacketAck`.
- Runtime target: under 10 minutes after images are available.

### Phase 4: Add snapshot PR path

Deliverables:

- Capture a snapshot from a successful Option B setup.
- Restore it in PR CI before packet relay.
- Validate snapshot compatibility before running the packet test.

Exit criteria:

- PR CI can skip admin recovery when snapshot compatibility passes.
- Snapshot refresh is automated or documented.

### Phase 5: Add nightly full bootstrap job

Deliverables:

- Optional scheduled job that builds from source and recreates clients/channels.
- Captures fresh snapshot artifact if successful.

Exit criteria:

- Nightly validates the full setup path.
- Nightly publishes a refreshed snapshot only after packet Ack passes.

## Timeouts

Every wait must fail with a useful message. No unbounded polling.

| Step | Timeout |
| --- | --- |
| Compose service health | 3 minutes |
| tx-indexer GraphQL availability | 1 minute |
| Gno `PacketSend` after `SendRaw` | 2 minutes |
| Voyager queue ready drain after enqueue | 2 minutes |
| Union `wasm-packet_recv` | 2 minutes |
| Union `wasm-write_ack` | 2 minutes |
| Gno `PacketAck` | 2 minutes |

On timeout, dump:

- Voyager `queue stats`
- Voyager `query-failed`
- new `failed` rows after baseline
- latest matching `done` rows for the packet hash
- relevant Gno/Union tx query output

## Cleanup Strategy

PR CI should prefer a clean Compose project per job:

```sh
docker compose -f e2e/union/docker-compose.yml down -v --remove-orphans
```

If using snapshots, restore into a new Docker volume set per run. Do not reuse
mutated volumes between jobs.

If a local debug run leaves ready timeout/retry rows, stop Voyager before
editing the DB, then defer or delete only rows created after the captured
baseline. CI should not share that DB with later runs.

## Assertions

The packet relay test must assert more than event presence:

- causality: `PacketAck.packet_hash == PacketSend.packet_hash`
- channel match: PacketSend source/destination channels match env ids
- ordering: Gno `PacketSend` height < Union `write_ack` height < Gno
  `PacketAck` height
- deduplication: exactly one Union `wasm-packet_recv`, one Union
  `wasm-write_ack`, and one Gno `PacketAck` for the packet hash within the run
  baseline
- no new Voyager failed rows after baseline
- new Voyager done rows contain the packet hash

## Snapshot Compatibility

Snapshots are valid only for the image/source versions that produced them.
Store a small manifest next to the snapshot:

```json
{
  "gno_ibc_git_sha": "<sha>",
  "gno_image": "gno-ibc-e2e-gno:<sha>",
  "voyager_image": "union-voyager-build:<sha>",
  "union_image": "ghcr.io/unionlabs/union:<digest>",
  "gno_chain_id": "dev",
  "union_chain_id": "union-devnet-1",
  "gno_channel_id": 3,
  "union_channel_id": 2
}
```

Before using a snapshot, CI must compare the manifest with the current images
and source SHA. If any value differs, skip the snapshot and run Option B setup.

## CI Failure Signals

Treat these as hard failures:

- no Gno `PacketSend`
- no Union `wasm-packet_recv`
- no Union `wasm-write_ack`
- no Gno `PacketAck`
- new Voyager failed rows after baseline
- new Voyager done rows do not contain the packet hash

Treat these as setup failures:

- Gno channel query returns `("" string)`
- Union channel query is not open
- tx-indexer GraphQL unavailable
- `10-gno: new val set cannot be trusted` still occurs after one auto-recovery
  retry
- missing Voyager plugin

## Open Decisions

1. Registry location for `gno-ibc-e2e-gno` and the Voyager fallback image.
2. Where to store the pre-encoded `GNO_PACKET_OPERAND_HEX` fixture.

## Recommendation

Start with Phase 1 and Phase 2: prove the image path first, then make the
existing Go packet test deterministic with Option B admin recovery. Add
snapshots only after that path is green from a clean Compose environment.
