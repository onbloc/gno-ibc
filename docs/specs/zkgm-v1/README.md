# ZKGM v1 App Spec

This document describes the current ZKGM v1 implementation. It covers the
proxy realm under
[gno.land/r/core/ibc/v1/apps/zkgm](../../../gno.land/r/core/ibc/v1/apps/zkgm),
the active implementation under
[gno.land/r/core/ibc/v1/apps/zkgm/v0/impl](../../../gno.land/r/core/ibc/v1/apps/zkgm/v0/impl),
and the stateless ABI package under
[gno.land/p/core/ibc/zkgm](../../../gno.land/p/core/ibc/zkgm).

The filesystem paths use `gno.land/*/core/...`, but the import paths published
by `gnomod.toml` use the `gnoswap` namespace:

- `gno.land/r/gnoswap/ibc/v1/apps/zkgm`
- `gno.land/r/gnoswap/ibc/v1/apps/zkgm/v0/impl`
- `gno.land/r/gnoswap/ibc/v1/apps/zkgm/v0/loader`
- `gno.land/p/gnoswap/ibc/zkgm`

## Scope

ZKGM is implemented as a stateful proxy realm plus an implementation realm. The
proxy owns all persistent app state, registers with IBC core, exposes public
send and admin entry points, and delegates instruction behavior to the active
implementation. The `v0/impl` realm contains the current dispatcher and opcode
handlers.

The public app surface includes:

- `Send` for structured ZKGM instructions
- `SendRaw` for CLI-friendly primitive arguments
- IBC app callbacks for channel lifecycle, receive, intent receive,
  acknowledgement, and timeout
- proxy state management through implementation, admin, receiver, ledger, and
  forward acknowledgement helpers

The channel version is `ucs03-zkgm-0`. `OnChannelOpenInit` and
`OnChannelOpenTry` reject any other local version. `OnChannelOpenTry` also
checks the counterparty version.

## Module Layout

| Module path | Filesystem path | Role |
|-------------|-----------------|------|
| `gno.land/r/gnoswap/ibc/v1/apps/zkgm` | `gno.land/r/core/ibc/v1/apps/zkgm/` | Proxy realm. Owns persistent app state and registers with IBC core. |
| `gno.land/r/gnoswap/ibc/v1/apps/zkgm/v0/impl` | `gno.land/r/core/ibc/v1/apps/zkgm/v0/impl/` | Active implementation. Provides dispatchers and opcode handlers. |
| `gno.land/r/gnoswap/ibc/v1/apps/zkgm/v0/loader` | `gno.land/r/core/ibc/v1/apps/zkgm/v0/loader/` | Initialization glue. Installs the implementation and registers the proxy app. |
| `gno.land/p/gnoswap/ibc/zkgm` | `gno.land/p/core/ibc/zkgm/` | Stateless ABI types, constants, path helpers, salt helpers, and event constants. |

Key proxy files:

| File | Purpose |
|------|---------|
| `proxy.gno` | Implementation pointer, receiver registry, proxy helpers, `BatchSend`, `WriteForwardAck`, and native release. |
| `ledger.gno` | Token origin, metadata image, channel balance, in-flight packet, and token bucket stores. |
| `admin.gno` | Admin, pause, rate-limit configuration, and global rate-limit toggle. |
| `app.gno` | `core.IApp` implementation and callback routing. |
| `send.gno` | Public `Send`, `SendRaw`, native coin capture, and core `PacketSend`. |
| `query.gno` | `GetConfig` and `Render`. |
| `types.gno` | Proxy interfaces, request types, in-flight types, update request, and config snapshot. |

Key implementation files:

| File | Purpose |
|------|---------|
| `impl.gno` | `ZkgmV1` singleton, `Send`, `Recv`, `IntentRecv`, `Ack`, `Timeout`, and rendering. |
| `dispatch.gno` | Shared verify, execute, ack, and timeout dispatchers. |
| `call.gno` | `OP_CALL` receiver dispatch and call acknowledgements. |
| `token_order.gno` | `OP_TOKEN_ORDER` verify, execution, refund, and settlement logic. |
| `batch.gno` | `OP_BATCH` child dispatch, batch acknowledgements, and child timeouts. |
| `forward.gno` | `OP_FORWARD` child packet construction and deferred parent ack resolution. |
| `channel_balance.gno` | Channel balance key construction and balance updates. |
| `predict.gno` | Wrapped token and call proxy account derivation. |
| `voucher.gno` | GRC20 voucher creation, minting, and burning. |
| `coins.gno` | Native sent-coin parsing and exact-match checks. |

## Minimal OP_CALL Flow

`OP_CALL` is the smallest ZKGM instruction. It carries application calldata to a
registered receiver realm on the destination chain. It does not move tokens,
does not batch child instructions, and does not change channel topology.

A user calls the source ZKGM proxy with
`Instruction{Version: INSTR_VERSION_0, Opcode: OP_CALL, Operand: Call}`. The
proxy delegates verification and packet encoding to the active implementation,
then asks IBC core to commit the packet. A relayer delivers the packet to the
destination chain. Destination core verifies the source packet commitment,
dispatches `OnRecvPacket` to the destination ZKGM proxy, and the proxy delegates
to `impl.Recv`. The implementation decodes the packet, executes `OP_CALL`,
looks up the registered receiver at `Call.ContractAddress`, and invokes
`receiver.OnZkgm`. The receiver result is wrapped in a ZKGM acknowledgement and
committed by destination core as a synchronous ack. A relayer then returns that
ack to source core, which calls source ZKGM `Ack`. Plain `OP_CALL` keeps no
source-side in-flight state, so its acknowledgement handler is a no-op unless
the rejected `Eureka` mode is present.

```mermaid
sequenceDiagram
  autonumber
  actor User
  participant SApp as Source ZKGM proxy
  participant SImpl as Source impl
  participant CoreS as Source IBC core
  participant Rel as Relayer
  participant CoreD as Destination IBC core
  participant DApp as Destination ZKGM proxy
  participant DImpl as Destination impl
  participant Recv as Destination receiver

  User->>SApp: Send(channel, timeout, salt, OP_CALL)
  SApp->>SImpl: Send(SendRequest)
  SImpl->>SImpl: dispatchVerify -> verifyCall
  SImpl->>SImpl: EncodeZkgmPacket(path=0, derived salt)
  SImpl-->>SApp: packet data bytes
  SApp->>CoreS: PacketSend(channel, data, timeout)
  CoreS-->>Rel: PacketSend event

  Rel->>CoreD: PacketRecv(packet, proof)
  CoreD->>DApp: OnRecvPacket(packet, relayerMsg)
  DApp->>DImpl: Recv(packet, relayerMsg)
  DImpl->>DImpl: DecodeZkgmPacket -> executeCall
  DImpl->>Recv: OnZkgm(CallEnv)
  Recv-->>DImpl: nil
  DImpl-->>DApp: RecvPacketResult{Success, ack}
  DApp-->>CoreD: RecvPacketResult
  CoreD-->>Rel: WriteAck event

  Rel->>CoreS: PacketAcknowledgement(packet, ack, proof)
  CoreS->>SApp: OnAcknowledgementPacket(packet, ack)
  SApp->>SImpl: Ack(packet, ack)
  SImpl->>SImpl: dispatchAck -> acknowledgeCall
```

Reading rules:

- Source and destination ZKGM proxies use the same module path, deployed on
  opposite chains.
- Source and destination implementations use the same `v0/impl` package,
  deployed on opposite chains.
- The destination receiver is any realm that registered itself with
  `RegisterReceiver`.
- Core proof verification is the standard packet flow from
  [IBC v1 Core](../ibc-v1-core/README.md). The sequence above focuses only on
  ZKGM-specific dispatch.

The send phase is covered by [Sending Packets](./sending-packets.md). Receiver
registration and `CallEnv` fields are covered by
[Receiver Registry](./receiver-registry.md). Opcode routing is covered by
[Instruction Dispatch](./instruction-dispatch.md) and the detailed `OP_CALL`
semantics are covered by [Call Instructions](./call-instructions.md). Wire envelope
layout is covered by [Wire Encoding](./wire-encoding.md).

## Module Reference

| File | Topic |
| --- | --- |
| [Proxy and Implementation](./proxy-and-impl.md) | Proxy state, impl pointer, authorization |
| [Sending Packets](./sending-packets.md) | Send entry point and predicted acks |
| [Receiver Registry](./receiver-registry.md) | Receiver registration |
| [Instruction Dispatch](./instruction-dispatch.md) | Opcode dispatch |
| [Wire Encoding](./wire-encoding.md) | Envelope, operand, ack, path encoding |
| [Call Instructions](./call-instructions.md) | Salt, path derivation, OP_CALL |
| [Token Order](./token-order.md) | TokenOrderV2 and predicted denoms |
| [Batch and Forward](./batch-and-forward.md) | Channel balance, OP_BATCH, OP_FORWARD |
| [Rate Limiting and Admin](./rate-limiting-admin.md) | Per-channel limits, admin entry points |
| [Events and Differences](./events-differences.md) | Queries, events, Union deltas |
