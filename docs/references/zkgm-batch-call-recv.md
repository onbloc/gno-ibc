# ZKGM Batch Call-Recv Pattern

> Related issue: [#86 — Implement Osmosis-style IBC Hook Equivalent via ZKGM Batch](https://github.com/onbloc/gno-ibc/issues/86)

## What this pattern does

This pattern allows a sender to settle tokens and invoke application logic
during the same ZKGM `PacketRecv`.

A sender constructs a single `OP_BATCH` packet containing:

```text
Batch
  ├── TOKEN_ORDER
  └── CALL
```

The `TOKEN_ORDER` settles or mints tokens for the destination account. The
`CALL` invokes a registered receiver realm with application-specific calldata.

From a user perspective, this provides a "transfer and execute" workflow similar
to Osmosis IBC Hooks, but without relying on ICS-20 memo parsing or middleware.

## Why not use IBC Hooks?

Osmosis IBC Hooks achieve a similar workflow by embedding application
instructions in the ICS-20 `memo` field:

```json
{
  "memo": "{\"wasm\":{\"contract\":\"osmo1...\",\"msg\":{\"swap\":{}}}}"
}
```

The receiving chain parses the memo and dispatches the embedded message to a
contract.

While effective, that approach requires:

- Memo-parsing middleware on the receiving chain
- JSON payload construction on the sender side
- Dependence on ICS-20 (IBC v1) transfer semantics

With ZKGM, application execution is represented explicitly as a `CALL`
instruction within the batch itself. No memo middleware is required, and the
application payload is carried directly in the instruction operand.

## Execution semantics

Batch execution is sequential.

```text
TOKEN_ORDER
    ↓
CALL
```

Each child instruction executes in order during the same `PacketRecv`, and the
batch acknowledgement contains one child acknowledgement per instruction.

Importantly, a batch is **not an atomic transaction**.

State changes produced by a successful child instruction remain committed even
if a later child returns a failure acknowledgement. For example, a successful
`TOKEN_ORDER` may mint or settle tokens even when a subsequent `CALL` fails.

Applications should therefore not assume rollback semantics across batch
boundaries.

If a child panics, the panic is converted into `ACK_ERR_ONLY_MAKER`, and batch
execution terminates according to the current ZKGM v1 execution rules.

---

## Implementing a Call receiver

Any realm can receive ZKGM `CALL` instructions by implementing `Zkgmable` and
registering itself with the ZKGM proxy.

### Receiver lookup

Receiver registration is keyed by the realm package path.

For a `CALL` instruction to be dispatched successfully, `ContractAddress` must
exactly match the registered realm path.

```go
ContractAddress: []byte("gno.land/r/myapp")
```

A mismatch between the registered path and the supplied `ContractAddress`
causes receiver lookup to fail and the `CALL` instruction to return an error
acknowledgement.

### Receiver implementation

```go
package myapp

import (
	"errors"

	z "gno.land/p/onbloc/ibc/union/zkgm"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
)

var receiver = &MyReceiver{}

func init(cur realm) {
	zkgm.RegisterReceiver(cross(cur), receiver)
}

type MyReceiver struct{}

// OnZkgm is called when a CALL instruction targeting this realm is received.
// env.Sender and env.Calldata are opaque bytes supplied by the sender.
func (r *MyReceiver) OnZkgm(cur realm, env z.CallEnv) error {
	// Decode env.Calldata and apply the requested action.
	return nil
}

func (r *MyReceiver) OnIntentZkgm(cur realm, env z.IntentCallEnv) error {
	return errors.New("intent calls are not supported")
}
```

`CallEnv` also exposes the ZKGM-derived proxy account, source and destination
channels, relayer bytes, and relayer message bytes. Treat `env.Calldata`,
`env.Sender`, `env.Relayer`, and `env.RelayerMsg` as untrusted inputs. Clone
reference-typed values before storing or mutating them across realm boundaries.

---

## Sending a batch

The sender constructs a `Batch` with:

1. A `TOKEN_ORDER` that settles or mints the token for the receiver.
2. A `CALL` whose `ContractAddress` is the registered receiver realm path.

```go
batch := z.Batch{Instructions: []z.Instruction{
	mustTokenOrderInstruction(z.TokenOrderV2{
		Sender:      []byte("cosmos1sender"),
		Receiver:    []byte(receiverAddress),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(100),
		QuoteToken:  []byte(wrappedDenom),
		QuoteAmount: u256.NewUint(100),
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
		Metadata:    metaBytes,
	}),
	mustCallInstruction(z.Call{
		Sender:           []byte("cosmos1sender"),
		ContractAddress:  []byte("gno.land/r/myapp"),
		ContractCalldata: []byte("swap:ugnot:uosmo:minOut=50"),
	}),
}}
```

The helper functions encode each child operand and set the matching ZKGM
instruction metadata:

```go
func mustTokenOrderInstruction(order z.TokenOrderV2) z.Instruction {
	bz, err := z.EncodeTokenOrderV2(order)
	if err != nil {
		panic(err)
	}
	return z.Instruction{
		Version: z.INSTR_VERSION_2,
		Opcode:  z.OP_TOKEN_ORDER,
		Operand: bz,
	}
}

func mustCallInstruction(call z.Call) z.Instruction {
	bz, err := z.EncodeCall(call)
	if err != nil {
		panic(err)
	}
	return z.Instruction{
		Version: z.INSTR_VERSION_2,
		Opcode:  z.OP_CALL,
		Operand: bz,
	}
}
```

`ContractCalldata` is opaque to ZKGM. The sender and receiver must agree on an
application encoding, such as a plain string, ABI payload, protobuf message, or
another domain-specific byte format.

Batch children are currently limited to `OP_TOKEN_ORDER` and `OP_CALL`.
Nested `OP_BATCH` and direct `OP_FORWARD` children are rejected in v1.

---

## Tests

| File | What it covers |
|---|---|
| `gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1/batch_test.gno` | Unit test coverage for `executeBatch` with `TOKEN_ORDER_KIND_INITIALIZE` + `CALL`, including ack and side-effect behavior. |
| `gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/e2e/scenarios/z24_v1_recv_batch_token_order_and_call_filetest.gno` | E2E filetest for full `PacketRecv` with a mock light client. It verifies the voucher balance, receiver call count, captured calldata, packet receipt, and written acknowledgement. |
