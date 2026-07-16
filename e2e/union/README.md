# Gno → Union Voyager E2E

This harness proves one deterministic path:

```text
Gno PacketSend → Union packet_recv → Union write_ack → Gno PacketAck
```

The tested inputs are pinned in `.gno-version` and `.env.example`; Compose uses
those commits as the local Gno and Voyager image tags.

## Prerequisites

- Docker Compose
- the Union Voyager checkout at the commit above (`UNION_VOYAGER_DIR`)
- Union's devnet running on RPC `26657`, EVM RPC `8545`, and beacon API `9596`
- the configured Union core and ZKGM contracts

Start and deploy the pinned Union checkout:

```sh
. e2e/union/.env.example
git -C "$UNION_VOYAGER_DIR" checkout "$UNION_COMMIT"
NO_BLOCKSCOUT=true "$UNION_VOYAGER_DIR/networks/run-linux-devnet.sh"
cd "$UNION_VOYAGER_DIR"
nix run .#cosmwasm-scripts.union-devnet.deploy-manager -- \
  --initial-admin union1jk9psyhvgkrt2cumz8eytll2244m2nnz4yt2g2 --allow-dirty
nix run .#cosmwasm-scripts.union-devnet.deploy -- --allow-dirty
nix run .#cosmwasm-scripts.union-devnet.whitelist-relayers -- \
  union1jk9psyhvgkrt2cumz8eytll2244m2nnz4yt2g2
```

The deployed Union state must contain client `4`, connection `3`, and channel
`2`. `TestGnoToUnionPacketRelay` validates their full counterparty IDs, port,
version, and open state before sending. The current contract addresses are in
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
state is written.

The Voyager Gno transaction key in the checked-in config and the admin mnemonic
in `.env.example` both derive to `g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5`;
the setup derives that address from the mnemonic before granting `RelayerRole`.

## Run the packet test

Pre-encode the ZKGM operand as described in the repository `AGENTS.md`, then:

```sh
RUN_PACKET_TESTS=1 \
GNO_PACKET_OPERAND_HEX=<hex> \
GNO_PACKET_SEND_COINS=1ugnot \
GNO_COMPOSE_DIR=. \
GOWORK=off GOCACHE=/private/tmp/gno-ibc-e2e-go-cache \
go test -v . -run '^TestGnoToUnionPacketRelay$'
```

The test captures Voyager queue/done/failed baselines, ignores historical
failures, checks exactly one receive/write-ack/ack for the packet hash, and
performs one bounded `force_update_client` retry for the known stale Gno client
failure.

## Troubleshooting

```sh
docker compose --env-file ../../.gno-version --env-file .env logs voyager
docker exec union-voyager-1 ./voyager \
  -c /config/voyager-config.gno-union.jsonc queue stats
docker exec union-voyager-1 ./voyager \
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
