# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

While the project is in the `0.x` series, the public API may change between
minor releases.

<!--
How to add entries:
- Keep an `## [Unreleased]` section at the top and add changes there as they land.
- On release, rename it to `## [X.Y.Z] - YYYY-MM-DD` and start a fresh Unreleased.
- Group entries under: Added, Changed, Deprecated, Removed, Fixed, Security.
- Bump version per SemVer: breaking -> major, feature -> minor, fix -> patch.
- Add a link reference for each version at the bottom of the file.
-->

## [0.1.0] - 2026-06-XX

Initial release. gno-ibc is an IBC v1 implementation for Gno, paired with
ZK-verified light clients and the ZKGM general message-passing application.
Realms publish under the `gno.land/r/onbloc/unionibc/v1/...` namespace.

### Release highlights

* **IBC v1 core**: client, connection, and channel handshakes plus the full
  packet lifecycle (send, receive, acknowledge, timeout) with batch support.
* **Two light clients**: CometBLS (Groth16 ZK header verification) and a
  state-lens ICS-23/MPT client for dual-layer L2-over-L1 verification.
* **ZKGM app**: four instruction types (TOKEN_ORDER, CALL, BATCH, FORWARD)
  with path-aware escrow, per-denom rate limiting, and admin recovery paths.

### Added

#### IBC core (`gno.land/r/onbloc/unionibc/v1/core`)

* Client management: create and update clients, track consensus states, query
  latest height, timestamp, and client status through a pluggable
  `ILightClient` interface and type registry.
* Connection handshake: full four-step flow (Init, Try, Ack, Confirm) with
  proof verification at each step.
* Channel handshake: full four-step flow with per-channel version negotiation
  and counterparty tracking.
* Packet lifecycle: send with commitment storage, receive with replay
  protection and timeout enforcement, acknowledgement, and timeout with
  proof-of-non-receipt.
* Batch operations: multi-packet send, multi-acknowledgement processing, and
  receipt of multiple packets from the same channel.
* Intent-based receive: market-maker fast path (`OnIntentRecvPacket`) for
  apps that opt in via `IIntentApp`.
* Port registration and app routing.
* Event emission for all client, connection, channel, and packet state
  transitions.

#### Light clients

* **CometBLS** (`.../lightclients/cometbls`): validator-set header
  verification via the `crypto/cometbls` Groth16 native, ICS-23 membership and
  non-membership proofs, misbehaviour detection with client freezing, and an
  admin-gated force-update recovery path for expired or frozen clients.
* **State-lens ICS-23/MPT** (`.../lightclients/statelensics23mpt`): dual-layer
  verification of L2 state against an L1 client, with Ethereum MPT membership
  and non-membership storage proofs and IBC commitment-key validation.

#### ZKGM app (`gno.land/r/onbloc/unionibc/v1/apps/zkgm`)

* App shell implementing `IApp` and `IIntentApp`, proxying to a pluggable
  versioned implementation (`v0`).
* Instruction types:
  * **TOKEN_ORDER**: path-aware escrow with INITIALIZE, ESCROW, and UNESCROW
    kinds, voucher (IBC-wrapped) and native token handling, and per-pair
    channel balance tracking.
  * **CALL**: remote module invocation with calldata routing.
  * **BATCH**: ordered nested instruction execution with rollback on failure
    and a single combined acknowledgement.
  * **FORWARD**: multi-hop cross-chain packet relay.
* Acknowledgement and timeout handling, including refund and retry on timeout
  and forward-child lifecycle management.
* Per-denom send-side rate limiting via configurable token buckets, with a
  global enable/disable switch.
* Admin operations: pause and unpause, per-denom bucket configuration, global
  rate-limit toggle, and `ForceSetImpl` for emergency implementation
  replacement without downtime.

#### Supporting packages (`gno.land/p/...`)

* ZKGM packet types, ABI encoding, and path/salt hashing.
* Solidity-compatible ABI codec (`encoding/abi`).
* Ethereum MPT storage-proof verification and IBC commitment-key derivation.
* Token-bucket rate limiter with configurable capacity and refill rate.
* ICS-23 proof specs, Merkle helpers, JSON parsing, and 256-bit unsigned
  integer arithmetic.
* Bindings to the `crypto/cometbls`, `crypto/bn254`, `crypto/keccak256`,
  `crypto/merkle`, `crypto/modexp`, and `crypto/ed25519` natives.

#### Tooling and tests

* Fixture generators for cross-implementation ground truth: ABI vectors,
  CometBLS ICS-23 proofs, Ethereum storage proofs, and full ZKGM scenarios
  (packet plus matching acknowledgement).
* gnokey smoke tests covering end-to-end client, channel, and packet flows.
* Filetests across the core and app realms.
* Calibrated gas tables for the IBC crypto natives.

### Security

* Packet callbacks follow checks-effects-interactions ordering to guard
  against reentrancy.
* Replay protection on packet receive via receipt tracking.
* Misbehaviour detection freezes a CometBLS client on conflicting headers.
* Send-side rate limiting and an admin pause path bound the blast radius of a
  compromised counterparty or relayer.

### Known limitations

* Channel close (`ChannelCloseInit` and `ChannelCloseConfirm`) is unsupported:
  the Union message format carries no channel id.
* Ordered channels are not supported; delivery follows the Union unordered
  model.
* TOKEN_ORDER `SOLVE` kind is not implemented and returns an error.
* ZKGM async call returns (Eureka pattern) and a BATCH instruction-length cap
  are not yet implemented.
* The state-lens client has no independent misbehaviour detection or
  force-update; both delegate to the underlying L1 client.
* Gas tables are calibrated on Apple M5 ARM64 and must be recalibrated on the
  target mainnet hardware before deployment.

[0.1.0]: https://github.com/onbloc/gno-ibc/releases/tag/v0.1.0
