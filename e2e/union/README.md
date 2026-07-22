# Direct Gno ↔ EVM Lens E2E

This harness proves two direct token packets:

```text
Gno ugnot → EVM ERC20 (Proof Lens)
EVM ERC20 → Gno GRC20 (state-lens/ics23/mpt)
```

Union is the settlement layer for both Lens clients, but it is not an
application-level packet hop. The suite creates only one Gno ↔ EVM connection
and channel.

Proof Lens keeps Solidity independent of Gno's store-proof format: Union
verifies the Gno membership proof and EVM verifies Union's committed result.
Voyager's Gno proof module and Union's Gno light client must still understand
the active Gno store proof and key format, including after the BPTree migration.
The reverse direction uses an EVM MPT proof through Union and
`state-lens/ics23/mpt` on Gno.

## Run the full cycle

The runner starts isolated Gno, Union, EVM, and Voyager services, creates the
four underlying clients and two Lens clients, opens the direct topology, sends
both packets, collects diagnostics, and removes the services on exit.

It requires Docker Compose, Nix, Go, Foundry, Rust `nightly-2025-12-05`, and a
clean Union Voyager checkout at the commit pinned in `.env.example`:

```sh
export UNION_VOYAGER_DIR=/path/to/union-voyager
git -C "$UNION_VOYAGER_DIR" checkout \
  "$(sed -n 's/^UNION_COMMIT=//p' e2e/union/.env.example)"
e2e/union/run-full-cycle-ci.sh
```

Diagnostics are written under `.e2e-artifacts/`. Share `run.log` first; for
failures, also include `voyager-failed.txt` and `gno-compose.log`. Set
`REBUILD_VOYAGER=1` to rebuild the pinned Voyager image instead of reusing it.

## Manual setup

Start and deploy the pinned Union devnet, then build the local stack:

```sh
cd e2e/union
cp .env.example .env
docker compose --env-file ../../.gno-version --env-file .env build gno voyager
docker compose --env-file ../../.gno-version --env-file .env up -d gno tx-indexer postgres voyager
docker compose --env-file ../../.gno-version --env-file .env --profile setup run --rm gno-whitelist
docker compose --env-file ../../.gno-version --env-file .env --profile setup run --rm gno-bootstrap
```

`setup-union-evm.sh` registers the pinned `trusted/evm/mpt` implementation on
Union. `setup-clients.sh` creates or discovers the four underlying clients and
the two Lens clients. Start continuous indexing for Gno, Union, and EVM before
running `setup-gno-evm-topology.sh`; packet tests never enqueue exact blocks.

For a manually prepared topology, run the direct tests with only client IDs and
the direct connection/channel IDs:

```sh
RUN_PACKET_TESTS=1 \
GNO_CLIENT_ID=<gno-cometbls-client> \
UNION_GNO_CLIENT_ID=<union-gno-client> \
UNION_EVM_CLIENT_ID=<union-trusted-evm-client> \
EVM_UNION_CLIENT_ID=<evm-cometbls-client> \
GNO_EVM_CLIENT_ID=<gno-state-lens-client> \
EVM_GNO_CLIENT_ID=<evm-proof-lens-client> \
GNO_EVM_CONNECTION_ID=<gno-direct-connection> \
EVM_GNO_CONNECTION_ID=<evm-direct-connection> \
GNO_EVM_CHANNEL_ID=<gno-direct-channel> \
EVM_GNO_CHANNEL_ID=<evm-direct-channel> \
GNO_SENDER_ADDR=<gno-sender-address> \
EVM_PRIVATE_KEY=<devnet-test-key> \
GOWORK=off GOCACHE=/private/tmp/gno-ibc-e2e-go-cache \
go test -count=1 -v . -run '^(TestGnoNativeToEVMProofLens|TestEVMERC20ToGnoStateLens)$'
```

Each direction requires one receive/write-ack, one successful source ack,
settled packet commitment, balance deltas, packet-specific Voyager done rows,
and no new failed rows. Gno → EVM additionally requires exactly one matching
Union `commit_membership_proof`; EVM → Gno validates the State Lens client and
its EVM MPT → Union membership → Gno verification topology. The final run check
rejects Force client/connection/channel activity, and packet checks reject
`intent_packet_recv`.

## Troubleshooting

```sh
docker compose --env-file ../../.gno-version --env-file .env logs voyager
docker compose --env-file ../../.gno-version --env-file .env exec voyager ./voyager \
  -c /config/voyager-config.gno-union.jsonc queue stats
docker compose --env-file ../../.gno-version --env-file .env exec voyager ./voyager \
  -c /config/voyager-config.gno-union.jsonc queue query-failed
```

Clean up with:

```sh
docker compose --env-file ../../.gno-version --env-file .env down -v --remove-orphans
```

The canonical gnokey query examples are in
`gno.land/r/onbloc/ibc/gnokey_tx_queries.md`.
