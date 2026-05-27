# ZKGM v1 App Spec

This document describes the current ZKGM app source files under
[gno.land/r/core/ibc/v1/apps/zkgm](../../gno.land/r/core/ibc/v1/apps/zkgm)
and ABI/types source files under
[gno.land/p/core/ibc/zkgm](../../gno.land/p/core/ibc/zkgm).

The filesystem paths use `gno.land/*/core/...`, but the ZKGM modules are
published with `gnoswap` import paths:

- `gno.land/r/gnoswap/ibc/v1/apps/zkgm`
- `gno.land/r/gnoswap/ibc/v1/apps/zkgm/v0/impl`
- `gno.land/p/gnoswap/ibc/zkgm`

## Scope

ZKGM is implemented as a proxy realm plus an implementation realm. The proxy
owns persistent app state and registers with IBC core. The implementation under
`v0/impl` provides the current instruction handlers and is exposed as the active
ZKGM implementation. Use the module/import paths above when importing these
realms from Gno code.

The public app surface includes:

- structured sends through `Send`
- CLI-friendly raw sends through `SendRaw`
- proxy state management, receiver registration, and async forward
  acknowledgement writing
- IBC app callbacks for receive, acknowledgement, timeout, and intent receive

## Proxy Responsibilities

The proxy realm stores and manages:

- admin, pause state, and implementation pointer
- channel balances
- registered call receivers
- token metadata images
- forward in-flight packet records
- rate-limit and operational guard state

The proxy delegates instruction-specific behavior to the active implementation.
The implementation calls back into the proxy for shared state such as channel
balances, receiver lookup, batch sends, and forward acknowledgement writes.

## Rate Limiting

The proxy owns the token bucket ledger used by ZKGM rate limiting. TokenOrderV2
verification charges the bucket for `INITIALIZE`, `ESCROW`, and `UNESCROW`
orders before accepting the packet-side token movement. Admin entry points can
configure bucket limits and toggle the global rate-limit kill switch.

## Sending Packets

`Send` accepts a typed ZKGM instruction and derives the sender salt for
user-originated packets. `SendRaw` accepts primitive arguments that can be passed
from `gnokey maketx call`, decodes the hex operand, and constructs the
instruction before sending.

Native-token sends depend on the previous realm being the user call frame.
Operationally, native `SendRaw` packets must be submitted as direct
`gnokey maketx call` transactions. A `maketx run` script changes the previous
realm and prevents the send coins from being captured as the user's native
token input.

`Send` and `SendRaw` dispatch to IBC core with the source app realm as the port
owner. The current packet path is committed by core, not by the ZKGM app.

## Instruction Dispatch

The v1 implementation routes instructions through dispatcher helpers:

- `dispatchVerify`
- `dispatchExecute`
- `dispatchAck`
- `dispatchTimeout`

Supported top-level instruction families are:

- `OP_CALL`
- `OP_TOKEN_ORDER`
- `OP_BATCH`
- `OP_FORWARD`

Verification, execution, acknowledgement, and timeout handling stay aligned by
using the same dispatcher surface for all instruction families.

## Call Instructions

Call instructions dispatch to a registered receiver realm. Receivers register
through the ZKGM proxy from their own realm.

The call environment carries the original caller, predicted proxy account,
path, source and destination channel information, sender bytes, calldata, and
relayer attribution fields. Receiver failures produce error acknowledgements
instead of committing partial receiver-side success.

## TokenOrderV2

TokenOrderV2 handles native and voucher token movement through ZKGM.

For native sends, the app verifies the sent coin against the order's base token
and amount. The send amount must exactly match the operand. Extra denoms, empty
sends, or mismatched amounts are rejected.

For initialize flows, token metadata is represented by implementation bytes and
initializer bytes. The quote token must match the predicted wrapped-token
address for the packet path, destination channel, base token, and metadata
image.

On receive, token orders update channel balances and mint or transfer the
corresponding voucher-side representation. On acknowledgement or timeout,
non-success paths refund through the token-order refund logic.

`TOKEN_ORDER_KIND_SOLVE` is defined in the ABI constants, but the current
implementation rejects SOLVE verification and receive paths as not implemented.

## Batch Instructions

Batch execution is intentionally constrained. Current batch children are limited
to `OP_CALL` and `OP_TOKEN_ORDER`.

Batch child salts are derived from the parent salt and child index. Child
acknowledgements are collected into a `BatchAck` and wrapped in an outer success
acknowledgement. A child `ACK_ERR_ONLY_MAKER` acknowledgement is propagated as
the parent batch acknowledgement and remaining children are skipped. Universal
error acknowledgements are distributed to children so token-order children can
apply refund behavior consistently.

The acknowledgement child count must match the batch instruction child count.

## Forward Instructions

Forward execution sends a child packet immediately through the proxy's batch
send path, stores the parent packet in the in-flight table, and returns an async
packet status to IBC core.

Current forward children may be `OP_CALL`, `OP_TOKEN_ORDER`, or `OP_BATCH`.
Direct Forward-of-Forward input is rejected during verification. Multi-hop
continuation can still rebuild a nested forward internally when required by the
path.

Child acknowledgement or timeout handling consumes the in-flight record and
writes the final parent acknowledgement through the proxy/core async
acknowledgement path.

## Wire Compatibility

ZKGM wire bytes are Solidity ABI compatible. Fixtures use the
`abi_encode_params` flavor, not plain top-level `abi.encode`. Compatibility
fixtures and regeneration rules are documented in
[Fixtures and Wire Compatibility](fixtures-and-wire-compatibility.md).

## Events

ZKGM packet activity is currently observed through IBC core events such as
`PacketSend`, `PacketRecv`, `WriteAck`, `PacketAck`, and `PacketTimeout`.
Reserved ZKGM-specific forward-child event constants exist, but are not emitted
by the current implementation. See [Event Catalog](events.md).

## Maintenance Notes

This spec should track current ZKGM behavior only. Keep historical planning
notes out of committed implementation specs.
