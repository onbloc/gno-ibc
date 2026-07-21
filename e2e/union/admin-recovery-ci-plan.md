# Historical Admin Recovery CI Setup Plan

> [!NOTE]
> This fixed-ID, single-packet plan has been superseded by
> `run-full-cycle-ci.sh`, which creates live topologies and validates the four
> bidirectional token packets. Keep this document only as background for the
> manual admin-recovery path; it is not the current CI procedure.

## Goal

Prove the PR-CI path with fixed Gno/Union IBC IDs before investing in
snapshots or a full Voyager handshake.

Target state:

- Gno chain: `dev`
- Union chain: `union-devnet-1`
- Gno connection: `5`
- Gno channel: `3`
- Union connection: `3`
- Union channel: `2`
- Union-side Gno client: `4`
- Gno ZKGM port: `gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm`

CI should start fresh services, create or validate that state through admin
recovery, send one Gno `SendRaw`, then let Voyager relay it to Gno `PacketAck`.

## Current Useful Pieces

- `e2e/union/docker-compose.yml` can run Gno, tx-indexer, Union devnet,
  Postgres, and Voyager.
- `gno-whitelist` already grants the relayer role on Gno.
- Gno core exposes admin recovery entrypoints:
  - `core.ForceConnectionOpenTry`
  - `core.ForceConnectionOpenAck`
  - `core.ForceConnectionOpenConfirm`
  - `core.ForceChannelOpenTry`
  - `core.ForceChannelOpenAck`
  - `core.ForceChannelOpenConfirm`
- The shortest validated Gno-side setup is:
  - `ConnectionOpenInit`
  - `ForceConnectionOpenAck`
  - `ChannelOpenInit`
  - `ForceChannelOpenAck`
- `TestGnoToUnionPacketRelay` now handles deterministic block enqueue after
  `PacketSend` and after Union `wasm-write_ack`.

## Proposed CI Flow

1. Clean local state.

   ```sh
   docker compose -f e2e/union/docker-compose.yml down -v --remove-orphans
   ```

2. Start base services.

   ```sh
   docker compose -f e2e/union/docker-compose.yml \
     --profile union-devnet --profile voyager up -d \
     gno tx-indexer union-devnet postgres voyager
   ```

3. Run Gno setup.

   - recover admin/relayer keys
   - grant the relayer role
   - deploy/register ZKGM if the image does not already include it
   - verify:

     ```gno
     gno.land/r/onbloc/ibc/union/core.HasApp([]byte("gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"))
     ```

4. Run admin recovery setup.

   Add a small setup runner under `e2e/union`, preferably a shell script that
   executes a checked-in Gno script through `gnokey maketx run`.

   The Gno script should:

   ```gno
   core.ConnectionOpenInit(
     cross(cur),
     core.NewMsgConnectionOpenInit(gnoClientId, unionClientId),
   )

   core.ForceConnectionOpenAck(
     cross(cur),
     core.NewMsgConnectionOpenAck(gnoConnectionId, unionConnectionId, nil, 0),
   )

   core.ChannelOpenInit(
     cross(cur),
     core.NewMsgChannelOpenInit(portId, portId, gnoConnectionId, zkgm.Version, relayer),
   )

   core.ForceChannelOpenAck(
     cross(cur),
     core.NewMsgChannelOpenAck(gnoChannelId, zkgm.Version, unionChannelId, nil, 0, relayer),
   )
   ```

   Use the emitted events or query output to confirm the allocated IDs. Do not
   assume `ConnectionOpenInit` or `ChannelOpenInit` returned an ID; they only
   emit events.

5. Validate fixed state before sending packets.

   ```gno
   gno.land/r/onbloc/ibc/union/core.QueryConnection(5)
   gno.land/r/onbloc/ibc/union/core.QueryChannel(3)
   ```

   Also verify Union already has an open channel `2` on connection `3` pointing
   back to Gno channel `3`. If fresh Union devnet does not provide this, add the
   matching Union-side setup command before Gno recovery.

6. Run the focused packet test.

   ```sh
   RUN_PACKET_TESTS=1 \
   GNO_PACKET_CONNECTION_ID=5 \
   GNO_PACKET_CHANNEL_ID=3 \
   UNION_PACKET_CONNECTION_ID=3 \
   UNION_PACKET_CHANNEL_ID=2 \
   UNION_GNO_CLIENT_ID=1 \
   GNO_PACKET_OPERAND_HEX=<pre-encoded-token-order> \
   GNO_PACKET_SEND_COINS=1ugnot \
   GNO_COMPOSE_DIR=e2e/union \
   GOWORK=off GOCACHE=/private/tmp/gno-ibc-go-cache \
   go test -v ./e2e/union -run TestGnoToUnionPacketRelay
   ```

## Implementation Tasks

### 1. Discover the real fresh-devnet baseline

Run fresh Compose once and record:

- whether Gno image already has core/ZKGM deployed
- whether Union devnet already has:
  - core contract address
  - ZKGM contract address
  - Gno client `1`
  - connection `3`
  - channel `2`
- exact container name for `uniond`

Exit criteria:

- A short note in `e2e/union/README.md` states which state is preloaded by the
  images and which state the setup script creates.

### 2. Add Gno admin recovery script

Add:

- `e2e/union/gno/admin-recovery.gno`
- `e2e/union/gno/admin-recovery.sh`

The shell script owns key recovery, `gnokey maketx run`, and post-run qeval
checks. Keep IDs configurable:

```sh
GNO_CLIENT_ID=...
UNION_CLIENT_ID=...
GNO_PACKET_CONNECTION_ID=5
UNION_PACKET_CONNECTION_ID=3
GNO_PACKET_CHANNEL_ID=3
UNION_PACKET_CHANNEL_ID=2
```

Exit criteria:

- Running the script twice either no-ops after validation or fails early with a
  clear "state already exists but differs" message.
- `QueryConnection(5)` and `QueryChannel(3)` are non-empty after a fresh run.

### 3. Wire setup into Compose/CI

Add one setup service or CI command:

```sh
docker compose -f e2e/union/docker-compose.yml \
  --profile setup up --no-build gno-whitelist gno-admin-recovery
```

Prefer a Compose setup service only if it reduces CI shell code. A direct CI
command is acceptable for the first version.

Exit criteria:

- Fresh Compose plus setup reaches the fixed IDs without manual commands.

### 4. Add CI workflow job

Add a PR job that:

- pulls configured images
- starts Compose
- runs whitelist/admin recovery setup
- runs `TestGnoToUnionPacketRelay`
- always dumps Voyager logs, queue stats, failed queue, Gno tx-indexer health,
  and Union tx query output on failure
- always runs `docker compose down -v --remove-orphans`

Exit criteria:

- CI validates one `PacketSend -> wasm-write_ack -> PacketAck` path.

### 5. Close the stale-client gap

If CI hits:

```text
10-gno: new val set cannot be trusted
```

implement the already documented recovery:

- generate Gno client-state bytes with Voyager `msg create-client --height`
- broadcast Union `force_update_client` for existing Union Gno client `1`
- retry `packet_recv` once

Exit criteria:

- the stale-client error either self-recovers once or fails with the exact
  generated command output.

## Minimal First PR

Do only these pieces first:

1. `admin-recovery.gno`
2. `admin-recovery.sh`
3. README command
4. one local verification run

Skip GitHub Actions until the local command works from a clean Compose project.

## Risks

- Fresh `union-devnet` may not already contain the desired Union-side client,
  connection, channel, or contracts. If so, Gno-only admin recovery is
  insufficient.
- Fixed IDs depend on the sequence counters. The setup must validate the ID
  before and after each creation step.
- `maketx run` is fine for admin recovery, but not for native-token `SendRaw`.
  Packet sending must remain `maketx call`.
- Do not add Voyager connection/channel CLI work unless admin recovery cannot
  make the fixed state. That is a larger feature and not needed for this proof.
