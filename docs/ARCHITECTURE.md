# Project Architecture

This document is a map of the first-party Gno packages and realms in this repository.\
It explains how the pure packages (`p/`) and stateful realms (`r/`) under the `onbloc` namespace fit together,\
what each one is responsible for, and how an IBC packet flows through them.

For per-module detail, follow the linked `README.md` of each component.\
For spec-level comparisons against the upstream references, see the [Spec Comparisons](README.md#spec-comparisons) section.

## Contracts

```
gno.land/
├── r/onbloc/ibc/                         # realms (stateful)
│   ├── union/
│   │   ├── core/                         # IBC Union core proxy
│   │   │   └── v1/                        #   └─ installed core implementation (ICore)
│   │   ├── apps/
│   │   │   ├── ucs03_zkgm/               # UCS03-ZKGM app proxy
│   │   │   │   └── v1/                    #   └─ installed ZKGM implementation (IApp)
│   │   │   └── transfer/                 # reference fungible-token transfer app
│   │   └── access/                       # shared access authority realm
│
└── p/onbloc/                             # packages (stateless)
    ├── ibc/union/
    │   ├── types/                        # host types, paths, commitment hashing
    │   ├── app/                          # IApp / IIntentApp callback interfaces
    │   ├── lightclient/                  # light-client Interface + status
    │   │   ├── cometbls/                 #   └─ CometBLS client
    │   │   └── state_lens/ics23_mpt/     #   └─ state-lens ICS23/MPT client
    │   └── zkgm/                         # ZKGM wire types, ABI, paths, predictions
    │       └── tokenbucket/              #   └─ per-denom rate-limit bucket
    ├── access/manager/                   # OpenZeppelin AccessManager port
    ├── encoding/{abi,rlp}/               # ABI / RLP codecs
    ├── verifier/evm/{mpt,storage}/       # EVM MPT & storage-slot proof verification
    └── diff/                             # text diff helper
```

## Layer Model

The system is split into stateless **pure packages** (reusable libraries, no on-chain state) \
and stateful **realms** (persistent contracts). \
Realms further use an **upgradeable proxy / implementation** split: \
a stable proxy realm owns identity, storage, and access gates, \
while a swappable `v1` implementation realm holds the protocol logic behind an interface.

Each box is one runtime layer. \
A public-facing realm (proxy) keeps the stable identity and forwards to its swappable `v1` implementation; \
arrows show the call direction. \
Everything ultimately depends on the pure packages at the bottom.

```
   users / relayers
          │
          ▼  call
┌─────────────────────────────────────────────────────────────────┐
│ APP REALMS                                                       │
│                                                                  │
│   apps/ucs03_zkgm  ──(proxy → impl)──▶  apps/ucs03_zkgm/v1       │
│   apps/transfer                                                  │
└─────────────────────────────────────────────────────────────────┘
          │
          ▼  IApp callbacks  (OnRecv / OnAck / OnTimeout)
┌─────────────────────────────────────────────────────────────────┐
│ CORE REALM                                                       │
│                                                                  │
│   core  ──(proxy → impl)──▶  core/v1                             │
│     │                                                            │
│     ├──▶ access         (shared authority realm: who-can-call)   │
│     └──▶ light clients  (cometbls · state_lens, via Interface)   │
└─────────────────────────────────────────────────────────────────┘
          │
          ▼  imports
┌─────────────────────────────────────────────────────────────────┐
│ PURE PACKAGES  (stateless, no on-chain state)                    │
│                                                                  │
│   ibc/union/types · app · lightclient · zkgm · tokenbucket       │
│   access/manager · encoding/{abi,rlp} · verifier/evm             │
└─────────────────────────────────────────────────────────────────┘
```

## Realms (`r/onbloc`)

Stateful contracts. Each public-facing realm is an upgradeable proxy that delegates protocol logic to a versioned implementation realm.

| Realm                          | Role                                                                                                                                                                                  | README                                                             |
| ------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------ |
| `ibc/union/core`               | Proxy realm for the IBC Union core host. Owns stable identity, access-managed entrypoints, app registry, persistent store, events, and the upgrade point for the core implementation. | [README](../gno.land/r/onbloc/ibc/union/core/README.md)            |
| `ibc/union/core/v1`            | Installed core implementation behind `ICore`. Supplies client, connection, channel, packet, proof, batch, and app-registry logic.                                                     | —                                                                  |
| `ibc/union/apps/ucs03_zkgm`    | Proxy realm for the UCS03-ZKGM app. Owns app identity, store, access gates, receiver registry, voucher-ledger capabilities, and the user-facing `Send`/`SendRaw` surface.             | [README](../gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/README.md) |
| `ibc/union/apps/ucs03_zkgm/v1` | Installed ZKGM implementation behind `IApp`. Holds opcode dispatch (Call, TokenOrder, Batch, Forward), escrow/voucher accounting, and rate limiting.                                  | —                                                                  |
| `ibc/union/apps/transfer`      | Reference fungible-token transfer app (forked from gno-realms).                                                                                                                       | [README](../gno.land/r/onbloc/ibc/union/apps/transfer/README.md)   |
| `ibc/union/access`             | Shared access authority. Owns the `manager.State` from `p/onbloc/access/manager`; core and app realms share it as a single authority, keyed per target by package path.               | [README](../gno.land/r/onbloc/ibc/union/access/README.md)          |

### Why the proxy / implementation split

The proxy realm keeps a **stable package path** (so other realms can import it once and never re-wire) and holds all persistent state, \
while protocol logic lives in a replaceable `v1` realm. \
Upgrading swaps the installed implementation through the proxy's `upgrade.gno` registration point, \
without moving state or changing the import path callers depend on. \
See the [core](../gno.land/r/onbloc/ibc/union/core/README.md) and [ZKGM proxy](../gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/README.md) READMEs for the file-by-file breakdown.

## Pure Packages (`p/onbloc`)

Stateless libraries. They define shared types and interfaces, and provide codecs and verification primitives. Realms import these; the packages never touch on-chain state.

### IBC Union

| Package                                      | Role                                                                                                                                                            | README                                                                              |
| -------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------- |
| `ibc/union/types`                            | Host types, message shapes, storage-path helpers, and commitment hashing shared across core, apps, light clients, and tests.                                    | [README](../gno.land/p/onbloc/ibc/union/types/README.md)                            |
| `ibc/union/app`                              | Interface package defining `IApp` (ordinary callbacks) and `IIntentApp` (proofless intent receive). Lets app realms implement callbacks without importing core. | [README](../gno.land/p/onbloc/ibc/union/app/README.md)                              |
| `ibc/union/lightclient`                      | Light-client `Interface` and status values used by core to store and route concrete clients.                                                                    | [README](../gno.land/p/onbloc/ibc/union/lightclient/README.md)                      |
| `ibc/union/lightclient/cometbls`             | CometBLS light-client object: header/proof verification and ICS23 proof chains.                                                                                 | [README](../gno.land/p/onbloc/ibc/union/lightclient/cometbls/README.md)             |
| `ibc/union/lightclient/state_lens/ics23_mpt` | State-lens client verifying L2 commitments via an L1 client id and ICS23/MPT proofs.                                                                            | [README](../gno.land/p/onbloc/ibc/union/lightclient/state_lens/ics23_mpt/README.md) |

### ZKGM

| Package                      | Role                                                                                                                                        | README                                                              |
| ---------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------- |
| `ibc/union/zkgm`             | UCS03-ZKGM wire types, ABI codecs, multi-hop path helpers, salt derivation, wrapped-token / call-proxy prediction, and receiver interfaces. | [README](../gno.land/p/onbloc/ibc/union/zkgm/README.md)             |
| `ibc/union/zkgm/tokenbucket` | Per-denom rate-limit bucket (refill from block time, charge on send).                                                                       | [README](../gno.land/p/onbloc/ibc/union/zkgm/tokenbucket/README.md) |

### Access & encoding primitives

| Package                | Role                                                                                                                       | README                                                  |
| ---------------------- | -------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------- |
| `access/manager`       | Reference by OpenZeppelin `AccessManager` — a state-transition library with no storage. The access realm owns its `State`. | [README](../gno.land/p/onbloc/access/manager/README.md) |
| `encoding/abi`         | Solidity ABI encode/decode used by ZKGM and commitment encoding.                                                           | —                                                       |
| `encoding/rlp`         | RLP encode/decode.                                                                                                         | —                                                       |
| `verifier/evm/mpt`     | EVVM Merkle-Patricia-Trie proof verification.                                                                              | —                                                       |
| `verifier/evm/storage` | EVM storage-slot proof verification used by state-lens clients.                                                            | —                                                       |

## Process Flows

Every public action follows the same proxy → implementation → pure-package layering.\
The four flows below — registering a light client, registering an app, sending coin out, and receiving it — cover the common lifecycle, including where the relayer and the counterparty Union chain come in.

> Throughout, a **relayer** is an off-chain process that watches both chains.\
> It carries packets and proofs between them: it reads a committed packet on the source chain, proves it to the destination chain, then reads the resulting acknowledgement and proves it back.\
> Nothing moves between chains without a relayer; the chains never talk directly.

### 1. Register a Light Client

A light client lets this chain verify the counterparty Union chain's state. Registration is two distinct steps:

1. **Register the client _type_.** `core.RegisterClient(clientType, clientImpl)` ([core/client.gno](../gno.land/r/onbloc/ibc/union/core/client.gno)) installs a light-client implementation under a type name — `cometbls` or `state-lens/ics23/mpt`.\
   This is relayer/admin-gated through the access realm and only registers the _code_ that knows how to verify that client kind.
2. **Create a client _instance_.** `core.CreateClient(msg)` takes a `ClientType`, the counterparty's initial `ClientStateBytes`, and `ConsensusStateBytes`, then asks the registered implementation to instantiate a concrete client and assigns it a client id.\
   The `ClientState`/`ConsensusState` bytes are a snapshot of the counterparty Union chain (its chain id, latest height, and a trusted consensus root) — supplied by the relayer that bootstraps the connection.

From here the relayer keeps the client fresh with `core.UpdateClient`, feeding new counterparty headers so the client can verify proofs at later heights.\
All later proof verification (steps 3–4 below) runs against the consensus state held by this client.

### 2. Register an App

An app realm (here, ZKGM) must register with core before it can send or receive packets, so core can route packet callbacks to it.

1. **App self-registers.** `ucs03_zkgm` calls `RegisterCoreApp` ([apps/ucs03_zkgm/register.gno](../gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/register.gno)), which crosses into `core.RegisterApp(AsIBCApp())`.\
   Core derives the **port id from the caller's package path**, so the app's identity is its realm path and no separate id needs minting. (`core.RegisterAppForPort` is the admin-only override for binding a port explicitly.)
2. **App registers its receivers.** For ZKGM's `OP_CALL` opcode, a downstream contract registers itself with `zkgm.RegisterReceiver(receiver)` from its own realm, keyed by that realm's package path.\
   Core has no part in this; it is internal ZKGM routing for who handles an inbound call.

No relayer or counterparty is involved in registration — it is purely local wiring.\
It only matters once a channel is opened over the registered client and packets start flowing through the registered port.

### 3. Packet Send

A user sends coin out to the counterparty chain.

1. **User → ZKGM proxy.** The user calls `zkgm.Send` / `zkgm.SendRaw` ([apps/ucs03_zkgm/transfer.gno](../gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/transfer.gno)) **as an EOA**, attaching the coin to move.\
   The proxy forwards to `ucs03_zkgm/v1`.
2. **Escrow.** v1 captures the attached coins via `unsafe.OriginSend()`, and `requireSentCoin` asserts they exactly match the order's `BaseToken`/`BaseAmount`.\
   The coins are **escrowed in the proxy realm's account**, and the per-channel escrow balance is increased (`channel_balance.gno`).
3. **Commit + emit.** v1 encodes the ZKGM packet envelope and calls `core.SendPacket` ([core/v1/packet.gno](../gno.land/r/onbloc/ibc/union/core/v1/packet.gno)).\
   Core checks the channel is open, writes a **packet commitment** at `BatchPacketsPath(...)` (value `COMMITMENT_MAGIC`), and emits a `PacketSend` event.

The commitment and event are the hand-off point: the **relayer** sees `PacketSend`, reads the commitment, and submits it with a membership proof to the counterparty Union chain, which runs its own verification and credits the recipient.\
The escrowed coin stays locked in the proxy account until a matching acknowledgement or timeout comes back.

### 4. Packet Receive

The inverse: a packet arrives from the counterparty and releases coin here. This path exercises every layer.

1. **Relayer → core proxy.** The relayer calls `core.PacketRecv(msg)` ([core/core.gno](../gno.land/r/onbloc/ibc/union/core/core.gno)), where `msg` carries the `Packets`, per-packet `RelayerMsgs`, the `Proof`, and the `ProofHeight`.\
   This entrypoint is relayer-gated through the access realm.
2. **Proof verification.** `core/v1` resolves the channel's light client (`lightclient.Interface`) and calls `VerifyMembership` against the consensus state at `ProofHeight` — proving the counterparty really committed this packet.\
   Inactive clients are rejected **before** any proof bytes are decoded (see the light-client proof rules in [AGENTS.md](../AGENTS.md)); CometBLS or state-lens packages do the actual cryptographic verification.
3. **Core → app.** Core records the packet receipt, looks up the destination app by port, and dispatches `IApp.OnRecvPacket` into the ZKGM proxy (pairing each packet with its `RelayerMsg`).
4. **ZKGM v1 dispatch.** The proxy forwards to `ucs03_zkgm/v1`, which decodes the envelope (via the `zkgm` pure package)\
   and routes each instruction through the opcode dispatcher (`dispatch.gno`): Call, TokenOrder, Batch, or Forward.
5. **TokenOrder effects.** The TokenOrder decreases the channel balance and sends coin from the proxy escrow account to the receiver (`escrow.gno`, via a realm-send banker).\
   It charges the rate-limit `tokenbucket` and pays the relayer its fee.
6. **Acknowledgement.** Core writes the acknowledgement at `BatchReceiptsPath(...)` and emits `WriteAck`.\
   The relayer reads this ack and proves it back to the counterparty so the original send can settle (or refund on failure). Forward packets defer this step via the async-ack path.

Acknowledgement and timeout on the sending side follow the same proxy → implementation → pure-package layering in reverse, consuming the ack/timeout proof the relayer brings back.
