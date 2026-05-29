# ZKGM Batch Call-Recv Pattern

> Related issue: [#86 — Implement Osmosis-style IBC Hook Equivalent via ZKGM Batch](https://github.com/onbloc/gno-ibc/issues/86)

## Why this pattern?

Osmosis IBC Hooks enable "transfer tokens and execute a contract atomically" by embedding a JSON payload in the ICS-20 `memo` field. The receiving chain parses the memo and calls a CosmWasm contract alongside the token receipt.

```json
{
  "memo": "{\"wasm\":{\"contract\":\"osmo1...\",\"msg\":{\"swap\":{}}}}"
}
```

This works, but requires:
- A memo-parsing middleware on the receiving chain
- JSON encoding on the sender side
- ICS-20 (IBC v1) only

**ZKGM on IBC v2 supports this pattern natively.** Instead of embedding instructions in a memo field, the sender constructs an `OP_BATCH` packet with a `TOKEN_ORDER` and a `CALL` instruction side by side. No middleware or memo parsing is needed.

```
Batch
  ├── TOKEN_ORDER  (mint wrapped tokens to receiver)
  └── CALL         (invoke a registered realm with arbitrary calldata)
```

Both instructions execute atomically within a single `PacketRecv`. If either fails, the batch ack reflects the per-instruction result independently.

---

## Implementing a Call receiver

Any realm can receive ZKGM Call instructions by implementing the `Zkgmable` interface and registering itself.

```go
package myapp

import (
    z    "gno.land/p/gnoswap/ibc/zkgm"
    zkgm "gno.land/r/gnoswap/ibc/v1/apps/zkgm"
)

func init(cur realm) {
    zkgm.RegisterReceiver(cross(cur), &MyReceiver{})
}

type MyReceiver struct{}

// OnZkgm is called when a CALL instruction targeting this realm is received.
// env.Sender   — original sender address on the source chain
// env.Calldata — arbitrary bytes encoded by the sender (e.g. swap parameters)
func (r *MyReceiver) OnZkgm(cur realm, env z.CallEnv) error {
    // decode env.Calldata and act on it
    return nil
}

func (r *MyReceiver) OnIntentZkgm(cur realm, env z.IntentCallEnv) error {
    return errors.New("not supported")
}
```

---

## Sending a batch

The sender constructs a `Batch` with a `TOKEN_ORDER` and a `CALL` pointing at the registered receiver realm.

```go
batch := z.Batch{Instructions: []z.Instruction{
    // 1. Transfer tokens to the receiver
    MustTokenOrderInstruction(z.TokenOrderV2{
        Sender:      []byte("cosmos1sender"),
        Receiver:    []byte(receiverAddress),
        BaseToken:   []byte("ugnot"),
        BaseAmount:  u256.NewUint(100),
        QuoteToken:  []byte(wrappedDenom),
        QuoteAmount: u256.NewUint(100),
        Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
        Metadata:    metaBytes,
    }),
    // 2. Invoke the receiver realm with action-specific calldata
    MustCallInstruction(z.Call{
        Sender:           []byte("cosmos1sender"),
        ContractAddress:  []byte("gno.land/r/myapp"),
        ContractCalldata: []byte("swap:ugnot:uosmo:minOut=50"),
    }),
}}
```

The `ContractCalldata` is opaque bytes — the format is defined by the receiving realm. The sender and receiver agree on an encoding (plain string, ABI, protobuf, etc.).

---

## Tests

| File | What it covers |
|---|---|
| `gno.land/r/core/ibc/v1/apps/zkgm/v0/impl/z_call_recv_test.gno` | Unit test: `executeBatch` with `TOKEN_ORDER_KIND_INITIALIZE` + `CALL`, asserts both acks succeed and balances are correct |
| `gno.land/r/core/ibc/v1/apps/zkgm/testing/e2e/scenarios/z24_v1_recv_batch_token_order_and_call_filetest.gno` | E2E filetest: full `PacketRecv` with mock light client, both instructions succeed atomically |
