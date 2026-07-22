# Live Union Relayer Channel E2E

This suite follows the Notion `Union Relayer 채널 연결 가이드` against the
predeployed `union-devnet-1`, a configured Union EVM, and Gno (`dev.ibc`)
topology. It does not start chains or deploy/register contracts.

## Prerequisites

- Gno already has Union core/ZKGM, CometBLS, and `state-lens/ics23/mpt`.
- Union already has its manager/IBC contracts and the Voyager relayer is
  whitelisted.
- EVM already has the confirmed IBC handler, multicall, ZKGM, CometBLS, and
  Proof Lens implementations/registrations.
- The Gno transaction indexer and all three RPC endpoints are reachable.
- PostgreSQL is reachable by Voyager.
- `bash`, `git`, `jq`, Docker, and GNU `timeout` (`coreutils`; `gtimeout` is
  also detected) are available.

The Voyager source is `union-voyager/e2e-test`, pinned in `.env.example` to
revision `9024777562dcaa01613017cd0b958569b85e243e`. The runner rejects a
different or dirty checkout before rendering the config. On the first live
run it builds `voyager-build.Dockerfile` with that checkout as its context and
tags the image with the pinned revision. The Dockerfile builds only the
Voyager binaries referenced by `config.jsonc.template`; Voyager and its
modules/plugins then run inside the local container.

The configured signer accounts must be funded and authorized. No EVM chain ID
or deployed address is assumed: copy all of them from the confirmed Union EVM
deployment record before applying.

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

For local runner tests only, `VOYAGER_BIN` may point to a fake host executable.
`VOYAGER_POLL_SECONDS` and `VOYAGER_TIMEOUT_SECONDS` shorten its polling.
Normal live runs do not execute host binaries from `target/debug`.

The local fake test broadcasts nothing and covers missing-client `null`
responses, creation order, dynamic Lens heights and relations, container-style
restarts, allocation races, and crash-after-enqueue duplicate prevention:

```sh
./run-channel-e2e-test.sh
```

## Protected manual workflow

`Gno Union EVM full cycle` is manual-only. Its `apply` input must be enabled
before the live job can run, and GitHub environment protection for
`union-relayer-e2e` should require an operator review. Configure public
deployment values, including `EVM_COMETBLS_CLIENT_IMPL` and
`EVM_PROOF_LENS_CLIENT_IMPL`, as environment variables and RPC URLs, the
database URL, and all private keys as environment secrets using the names in
`.env.example`.
The workflow checks out `union-voyager` at the pinned revision above, runs this
same runner, and uploads only its sanitized artifact directory on success or
failure.
