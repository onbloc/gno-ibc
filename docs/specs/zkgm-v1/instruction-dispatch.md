# Instruction Dispatch

The implementation routes all instruction families through four dispatcher
helpers:

- `dispatchVerify` — send-time validation. Checks rate limits, accepts the
  user-attached coins, and ensures the operand is well-formed.
- `dispatchExecute` — receive-time execution. Decodes the operand, performs
  side effects, and returns a `RecvPacketResult`.
- `dispatchAck` — source-side acknowledgement handling. Refunds escrow on
  failure, marks success cases as no-ops.
- `dispatchTimeout` — source-side timeout handling. Mirrors the failure
  branch of `dispatchAck`.

Supported opcodes:

| Opcode | Value | Operand version | Operand type |
|--------|-------|-----------------|--------------|
| `OP_FORWARD` | `0x00` | `INSTR_VERSION_0` | `Forward` |
| `OP_CALL` | `0x01` | `INSTR_VERSION_0` | `Call` |
| `OP_BATCH` | `0x02` | `INSTR_VERSION_0` | `Batch` |
| `OP_TOKEN_ORDER` | `0x03` | `INSTR_VERSION_2` | `TokenOrderV2` |

Unsupported opcodes return `zkgm/v1: unsupported opcode`. Operand version
mismatches return opcode-specific unsupported-version errors.

`dispatchExecute` catches panics and converts them into a failed
`RecvPacketResult` whose ack is `universalErrorAck()`. Decode errors return
`PacketStatusUnknown` with an error so the caller can surface the failure.
This is the source of the (success-tag, `ACK_ERR_ONLY_MAKER` inner-ack)
combination documented in [Salt, Path, and Call](./salt-path-and-call.md).
