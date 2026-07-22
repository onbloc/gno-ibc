# Gno → Union Voyager E2E

This harness proves two routed token paths using four packets, plus two direct
Proof Lens packets:

```text
Gno ugnot → Union CW20 → EVM ERC20
EVM ERC20 → Union CW20 → Gno GRC20
Gno ugnot → EVM ERC20 (Proof Lens)
EVM ERC20 → Gno GRC20 (Proof Lens)
```

The tested inputs are pinned in `.gno-version` and `.env.example`; Compose uses
those commits as the local Gno and Voyager image tags.

## Run the full cycle

The full-cycle runner starts isolated Gno, Union, EVM, and Voyager services,
creates live clients and three topologies, runs the readiness checks and all
six token packets, collects diagnostics, and removes the services on exit.

It requires Docker Compose, Nix, Go, Foundry, Rust
`nightly-2025-12-05`, and a clean Union Voyager checkout at the pinned commit:

```sh
export UNION_VOYAGER_DIR=/path/to/union-voyager
git -C "$UNION_VOYAGER_DIR" checkout \
  "$(sed -n 's/^UNION_COMMIT=//p' e2e/union/.env.example)"
e2e/union/run-full-cycle-ci.sh
```

Local diagnostics are written under `.e2e-artifacts/`. Share `run.log` first;
for failures, also include `voyager-failed.txt` and `gno-compose.log`. GitHub
Actions runs the same script for pull requests, pushes to `main`, the daily
schedule, and manual dispatch, and retains its diagnostic artifact for 7 days.

The runner reuses the pinned `union-voyager-build:<UNION_COMMIT>` image when it
is already present. Set `REBUILD_VOYAGER=1` to rebuild it explicitly.

## Manual setup prerequisites

The commands below are for running and debugging the services individually.

- Docker Compose
- the Union Voyager checkout pinned in `.env.example` (`UNION_VOYAGER_DIR`)
- Union's devnet running on RPC `26657`, EVM RPC `8545`, and beacon API `9596`
- the configured Union core and ZKGM contracts

Start and deploy the pinned Union checkout:

```sh
git -C "$UNION_VOYAGER_DIR" checkout \
  "$(sed -n 's/^UNION_COMMIT=//p' e2e/union/.env.example)"
NO_BLOCKSCOUT=true "$UNION_VOYAGER_DIR/networks/run-linux-devnet.sh"
cd "$UNION_VOYAGER_DIR"
nix run .#cosmwasm-scripts.union-devnet.deploy-manager -- \
  --initial-admin union1jk9psyhvgkrt2cumz8eytll2244m2nnz4yt2g2 --allow-dirty
nix run .#cosmwasm-scripts.union-devnet.deploy -- --allow-dirty
nix run .#cosmwasm-scripts.union-devnet.whitelist-relayers -- \
  union1jk9psyhvgkrt2cumz8eytll2244m2nnz4yt2g2
```

The Gno ↔ Union packet test validates its configured topology before sending.
The direct Union ↔ Ethereum test uses separately created client, connection,
and channel IDs and never reuses a topology with a mismatched counterparty,
port, owner, or version. The current contract addresses are in
`voyager-config.gno-union.jsonc`.

## Build and start

```sh
cd e2e/union
cp .env.example .env
docker compose --env-file ../../.gno-version --env-file .env build gno voyager
docker compose --env-file ../../.gno-version --env-file .env up -d gno tx-indexer postgres voyager
```

The Gno Docker build reads `GNO_REPO` and `GNO_COMMIT` directly from the root
`.gno-version`; there is no floating fallback.

## Deterministic Gno setup

The setup services are independently rerunnable. Use `run --rm`, not attached
`up`:

```sh
docker compose --env-file ../../.gno-version --env-file .env --profile setup run --rm gno-whitelist
docker compose --env-file ../../.gno-version --env-file .env --profile setup run --rm gno-bootstrap
docker compose --env-file ../../.gno-version --env-file .env --profile setup run --rm gno-admin-recovery
```

`gno-bootstrap` installs the core and ZKGM implementations, registers the app,
and registers both light clients. `gno-admin-recovery` creates and validates
Gno connection `5` and channel `3`; a mismatched existing record fails before
state is written. These fixed IDs belong only to the manual admin-recovery
path; the full-cycle runner creates and discovers live topology IDs.

The Voyager Gno transaction key in the checked-in config and the test mnemonic
in `.env.example` both derive to `g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5`;
the setup derives that address before granting `RelayerRole`.

## Deterministic Union EVM light-client setup

The direct Union ↔ Ethereum link requires `trusted/evm/mpt` on the Union core.
The setup is independently rerunnable and exits without broadcasting when the
registered implementation and code already exist:

```sh
e2e/union/setup-union-evm.sh
```

If the pinned artifact has not been built, the script stops and prints the
exact pinned build command. Contract deployment and client registration remain
a setup operation; packet tests never perform them implicitly.

## Run the token scenarios

The test queries the live Union token-minter configuration, creates destination
metadata and quote tokens, deploys Union's existing `TestERC20` to EVM, and
broadcasts all four direct packets without a pre-written fixture:

```sh
RUN_PACKET_TESTS=1 \
GNO_PACKET_CONNECTION_ID=<live-gno-connection> \
GNO_PACKET_CHANNEL_ID=<live-gno-channel> \
UNION_PACKET_CONNECTION_ID=<live-union-gno-connection> \
UNION_PACKET_CHANNEL_ID=<live-union-gno-channel> \
UNION_GNO_CLIENT_ID=<live-union-gno-client> \
UNION_EVM_CONNECTION_ID=<live-union-evm-connection> \
UNION_EVM_CHANNEL_ID=<live-union-evm-channel> \
UNION_EVM_CLIENT_ID=<live-union-evm-client> \
EVM_UNION_CONNECTION_ID=<live-evm-connection> \
EVM_UNION_CHANNEL_ID=<live-evm-channel> \
EVM_UNION_CLIENT_ID=<live-evm-client> \
GNO_SENDER_ADDR=<gno-sender-address> \
EVM_PRIVATE_KEY=<devnet-test-key> \
GOWORK=off GOCACHE=/private/tmp/gno-ibc-e2e-go-cache \
go test -v . -run '^TestTokenBridgeScenarios$'
```

Each packet checks one receive/write-ack/ack, a success acknowledgement, source
commitment settlement, balance deltas, packet-specific Voyager done rows, and
no failed rows after its baseline. The 18-decimal EVM asset uses an amount
divisible by `10^12` and verifies the downscaled Gno voucher balance.

## Troubleshooting

```sh
docker compose --env-file ../../.gno-version --env-file .env logs voyager
docker compose --env-file ../../.gno-version --env-file .env exec voyager ./voyager \
  -c /config/voyager-config.gno-union.jsonc queue stats
docker compose --env-file ../../.gno-version --env-file .env exec voyager ./voyager \
  -c /config/voyager-config.gno-union.jsonc queue query-failed
curl -fsS http://localhost:48546/graphql/query \
  -H 'content-type: application/json' \
  --data '{"query":"{ latestBlockHeight }"}'
```

Clean up every run with:

```sh
docker compose --env-file ../../.gno-version --env-file .env down -v --remove-orphans
```

The canonical gnokey query examples are in
`gno.land/r/onbloc/ibc/gnokey_tx_queries.md`.
