# Live Union Relayer Channel E2E

This suite follows the Notion `Union Relayer 채널 연결 가이드` against the
predeployed `union-devnet-1`, a configured Union EVM, and Gno (`dev.ibc`)
topology. It does not start chains or deploy/register contracts.

## Acceptance scenarios

The Go runner is organized around five acceptance contracts:

1. **S1 — Fresh channel establishment.** Index Union and Gno; create the four
   underlying clients and two Lens clients in guide order; apply disjoint EVM
   allowlists and index EVM; open the EVM connection and Gno channel; verify
   all client relations, both `OPEN` handshakes, ports, version, unchanged
   unrelated failed work, and sanitized evidence.
2. **S2 — Completed resume.** Load and validate one complete S1 state before
   any side effect, verify the same topology, and broadcast no client,
   connection, or channel transaction. Reject incomplete completed state.
3. **S3 — ERC20 EVM to Gno.** Validate token code and 18 decimals; mint,
   approve, and send one TokenOrder; observe exactly one `PacketSend`,
   `PacketRecv`, `WriteAck`, and `PacketAck`; require a cleared commitment,
   exact balance deltas, unchanged unrelated failed work, and sanitized
   evidence.
4. **S4 — Failure acknowledgement and refund.** Given matching failure
   acknowledgements, require a cleared commitment, full sender refund, and no
   voucher increase; save sanitized evidence and return failure.
5. **S5 — Ambiguous submission.** Persist intent before connection, channel,
   mint, approve, and send writes. A `*-submitting` resume never repeats the
   write; it advances only when the exact external result is observable and
   otherwise fails as ambiguous.

S1-S3 are protected live scenarios. S4 uses focused result classification
unless CI provides deterministic safe failure injection. S5 uses focused
transition tests rather than a fake multi-chain E2E.

The package dependency direction is:

```text
cmd
 ├─ config
 └─ scenario
     ├─ voyager ─┐
     ├─ evm      ├─ process
     ├─ gno      ┘
     └─ state
```

Packages are added only when their owning phase needs them. `scenario` owns
order, resume decisions, and evidence; external-system packages own protocol
details; `state` owns durable data; `config` owns validation and rendering;
`process.Executor` is the only command-execution interface.

## Prerequisites

- Gno already has Union core/ZKGM, CometBLS, and `state-lens/ics23/mpt`.
- Union already has its manager/IBC contracts and the Voyager relayer is
  whitelisted. Its IBC host must also have `trusted/evm/mpt` registered.
- EVM already has the confirmed IBC handler, multicall, ZKGM, CometBLS, and
  Proof Lens implementations/registrations.
- The Gno transaction indexer and all three RPC endpoints are reachable.
- PostgreSQL is reachable by Voyager.
- `bash`, `git`, Docker, and Go 1.26.2 are available.
- The optional packet scenario also requires `cast` and `gnokey`.

The Voyager source is `union-voyager/e2e-test`, pinned in `.env.example` to
revision `9024777562dcaa01613017cd0b958569b85e243e`. The runner rejects a
different or dirty checkout before rendering the config. On the first live
run it builds `voyager-build.Dockerfile` with that checkout as its context and
tags the image with the pinned revision. It verifies and runs the immutable
image ID emitted by Docker rather than the mutable tag. The Dockerfile builds
only the Voyager binaries referenced by `config.jsonc.template`; Voyager and
its modules/plugins then run inside the local container.

The configured signer accounts must be funded and authorized. No EVM chain ID
or deployed address is assumed: copy all of them from the confirmed Union EVM
deployment record before applying.

## Environment values

Copy `.env.example` to a private mode-`0600` `.env`. The runner rejects a file
readable by group or other users.

| Group | Variables | How to obtain them |
| --- | --- | --- |
| Chain identity | `UNION_CHAIN_ID`, `EVM_CHAIN_ID`, `GNO_CHAIN_ID` | Query each RPC and compare it with the intended deployment. The local topology uses `union-devnet-1` and `dev.ibc`; the EVM ID comes from `eth_chainId`. |
| Voyager source | `UNION_VOYAGER_DIR`, `UNION_VOYAGER_REVISION` | Check out `union-voyager/e2e-test` at the pinned SHA. The checkout must be clean. |
| Public deployment | `UNION_IBC_HOST_CONTRACT`, `EVM_IBC_HANDLER`, `EVM_MULTICALL`, `EVM_COMETBLS_CLIENT_IMPL`, `EVM_PROOF_LENS_CLIENT_IMPL`, `GNO_IBC_CORE_REALM`, `GNO_ZKGM_PORT`, `EVM_ZKGM_CONTRACT`, `GALOIS_PROVER_ENDPOINT` | Copy from the confirmed deployment output or on-chain registry. Do not guess addresses from an older environment. |
| Endpoints | `UNION_RPC_URL`, `EVM_RPC_URL`, `GNO_RPC_URL`, `GNO_TX_INDEXER_RPC_URL`, `VOYAGER_DATABASE_URL` | Use endpoints reachable from the Voyager container. For host services on Docker Desktop, use `host.docker.internal` instead of `localhost`. If the host cannot resolve that name, set the optional `EVM_PACKET_RPC_URL`, `GNO_PACKET_RPC_URL`, and `GNO_PACKET_INDEXER_RPC_URL` to host-reachable URLs for the packet checks. Use a dedicated PostgreSQL database for each fresh live run. |
| Signers | `TRUSTED_MPT_PRIVATE_KEY`, `UNION_PRIVATE_KEY`, `EVM_PRIVATE_KEY`, `GNO_PRIVATE_KEY` | Supply `0x` plus 64 hex characters. Union, EVM, and Gno keys must identify funded and authorized test accounts; the trusted-MPT key may be a fresh test-only key. Store all four as secrets. |
| Optional packet | `EVM_TEST_ERC20`, `GNO_RECIPIENT`, `EVM_TEST_AMOUNT` | Use a deployed 18-decimal mintable test token, a Gno recipient, and an amount divisible by `10^12`. |
| Output/tuning | `E2E_ARTIFACT_DIR`, `E2E_STATE_FILE`, `VOYAGER_IMAGE`, `VOYAGER_RUST_LOG`, `E2E_TIMEOUT_SECONDS`, `E2E_POLL_SECONDS`, `VOYAGER_COMMAND_TIMEOUT_SECONDS`, `VOYAGER_EVM_REFRESH_SECONDS`, `VOYAGER_STOP_TIMEOUT_SECONDS`, `E2E_CLEANUP_TIMEOUT_SECONDS` | Defaults are suitable locally. Keep the state file under the artifact directory; increase the scenario timeout when EVM finality is slow. The cleanup timeout must exceed the Docker stop timeout. The runner refreshes Voyager at most three times when a newly created EVM client remains hidden by a stale state-module read. |

To create a new EVM test account, use `cast wallet new`, then fund its address
and grant any token permissions required by the packet test. A standalone
trusted-MPT key can be generated without printing an existing mnemonic:

```sh
openssl rand -hex 32
# Store the result as TRUSTED_MPT_PRIVATE_KEY with a leading 0x.
```

For the public local-dev mnemonic, the repository helper derives the Cosmos/Gno
raw key at `44'/118'/0'/0/0`. From the repository root, read the mnemonic
without echoing it or placing it in shell history:

```sh
read -s TEST_MNEMONIC
printf '%s' "$TEST_MNEMONIC" | go run ./e2e/union/gno/testdata/mnemonic-raw-key
unset TEST_MNEMONIC
```

Use that result for `GNO_PRIVATE_KEY`, and for `UNION_PRIVATE_KEY` only when the
same derived account is the funded Union relayer. Production or shared testnet
keys should come from the environment's secret manager, not this helper.

The runner does not deploy light-client contracts. Before running against a
fresh Union chain, query `UNION_IBC_HOST_CONTRACT` and confirm that client type
`trusted/evm/mpt` resolves to a deployed contract. If it is absent, the chain
provisioning step must store the trusted-MPT WASM, instantiate/migrate it,
assign the expected admin, and register it before this E2E starts.

```sh
uniond query wasm contract-state smart "$UNION_IBC_HOST_CONTRACT" \
  '{"get_registered_client_type":{"client_type":"trusted/evm/mpt"}}' \
  --node "$UNION_RPC_URL" -o json
```

## Structure and execution flow

```text
run-channel-e2e.sh
  -> verify and load the private mode-0600 environment
  -> execute the scenario-first Go runner
  -> build focused Voyager image from the pinned union-voyager checkout
  -> run Voyager modules/plugins in one local container
  -> connect to Union, EVM, Gno, Gno indexer, and PostgreSQL
  -> write sanitized state and verification artifacts
```

A fresh `--apply` run performs one ordered flow:

1. Render a secret-bearing runtime config in a private temporary directory.
2. Index Union and Gno, and save the EVM finalized height that starts this run.
3. Create the six clients in the guide order: Gno→Union, Union→Gno,
   Union→EVM, EVM→Union, Gno→EVM Lens, and EVM→Gno Proof Lens.
4. Index EVM from the saved height after both EVM clients settle, read the
   underlying clients' live metadata, calculate both Lens configs, rebuild
   disjoint EVM batch allowlists, and restart Voyager.
5. Initiate the connection on EVM and the ZKGM channel on Gno.
6. Verify both sides are open and cross-reference the expected clients,
   connection/channel IDs, ports, and `ucs03-zkgm-0` version.
7. Reject unrelated new Voyager failed work and write sanitized artifacts.

The optional `--erc20-to-gno` phase then mints and approves the configured test
token, sends one packet, and verifies Gno receive/ack events, the EVM ack and
commitment, and the exact balance changes.

### Queue completion observation

Voyager moves successfully processed queue items to PostgreSQL `done` and
terminal errors to `failed`. Packet-related items can be correlated by the
packet hash stored in their JSON payload. These tables are useful as a fast
signal, but the pinned Voyager revision does not emit `pg_notify` calls and
does not install notification triggers. The current runner therefore checks
`failed` through the Voyager CLI and treats on-chain state/events as the final
result.

If the database provisioning later adds a versioned `done`/`failed` notification
trigger, the listener should receive only the queue ID, query the corresponding
row, and match the expected packet hash and event type. It must query once
before and after `LISTEN` so a notification sent during startup cannot be lost;
notification is a wake-up signal, while the tables remain the source of truth.

## Configure and preflight

```sh
cd e2e/union
install -m 600 .env.example .env
# Fill the Union EVM chain ID/addresses, endpoints, keys, and database URL.
./run-channel-e2e.sh
```

The runner verifies the pinned Voyager checkout, renders a mode-`0600`
temporary config, checks JSON structure, private-key shape, placeholders, the
three chain IDs, all six client module combinations, and disjoint EVM batch
allowlists, then deletes the config. It never prints secret values.

`--apply` is the explicit authorization boundary for indexing and client
creation:

```sh
./run-channel-e2e.sh --apply
```

The runner first starts the container with empty EVM batch allowlists,
queries the next two EVM client IDs, renders disjoint bootstrap allowlists,
and restarts before indexing. It captures the current failed-work ID, indexes
Union, EVM, and Gno, then always creates and verifies six new clients in
the guide's order. Any allocation change fails instead of silently using a
stale allowlist. Lens heights come from the new underlying clients'
`client-meta` responses. It renders the final EVM batch allowlists from
live client types, restarts Voyager, and verifies all six clients again. It
then opens the EVM connection and Gno ZKGM channel at captured next IDs
and verifies both sides' states, references, ports, and version.
Before the first index/client enqueue it atomically writes a mode-`0600`
bootstrap checkpoint. A failed bootstrap cannot be started again in the same
artifact directory, preventing duplicate client creation.

Sanitized state, command payloads, state responses, and a summary are written
to `E2E_ARTIFACT_DIR`. Resume verification never broadcasts:

```sh
./run-channel-e2e.sh --resume
```

`--resume` requires the saved mode-`0600` `E2E_STATE_FILE`, re-verifies all
six clients and the exact connection/channel IDs, and never broadcasts by
itself. The state binds the EVM chain ID and a lowercase fingerprint of the
IBC Handler, multicall, ZKGM, CometBLS client implementation, and Proof Lens
client implementation addresses. Changing any deployment address rejects the
saved state instead of resuming against a different topology.
Use both flags to continue a saved run at a known safe boundary:

```sh
./run-channel-e2e.sh --resume --apply
```

The state is written as `connection-submitting` or `channel-submitting`
before enqueue. If a process dies after enqueue but before the next checkpoint,
the runner accepts matching on-chain progress but never automatically enqueues
the ambiguous operation again.

## Optional EVM ERC20 packet

Set `EVM_TEST_ERC20` to an already deployed test token that exposes
`mint(address,uint256)`, set `GNO_RECIPIENT`, and choose an 18-decimal
`EVM_TEST_AMOUNT` divisible by `10^12`. The existing EVM key signs the
mint, approval, and ZKGM send. The packet phase is a separate explicit write
boundary and runs only after the direct channel has been verified:

```sh
./run-channel-e2e.sh --resume --apply --erc20-to-gno
```

The runner checks token code and 18 decimals, sends one INITIALIZE TokenOrder,
then requires one Gno `PacketRecv`/successful `WriteAck`, one successful
EVM `PacketAck`, an inactive source commitment, exact sender/escrow and
decimal-adjusted Gno voucher deltas, and no new Voyager failed work. It writes
only IDs, public addresses, hashes, and balance deltas to
`packet-summary.json`.

Mint, approval, and packet send each have a pre-submit checkpoint. If the
process loses a command result, a later invocation refuses to repeat that
write; inspect the saved state and the chain before choosing a new artifact
directory. A completed packet state can be re-verified without another write.
Successful `packet-complete` checkpoints written by the fixed-point shell are
normalized in memory and retain the same zero-write resume behavior.

## Protected manual workflow

`Gno Union EVM full cycle` is manual-only. Its `apply` input must be enabled
before the live job can run, and GitHub environment protection for
`union-relayer-e2e` should require an operator review. Configure public
deployment values, including `EVM_COMETBLS_CLIENT_IMPL` and
`EVM_PROOF_LENS_CLIENT_IMPL`, as environment variables and RPC URLs, the
database URL, and all private keys as environment secrets using the names in
`.env.example`.
The database URL must identify the dedicated fresh Voyager database provisioned
for the protected run. The workflow checks out `union-voyager` at the pinned
revision above, runs fresh S1, zero-broadcast S2, and optional S3 in order, and
uploads only its sanitized artifact directory on success or failure.
