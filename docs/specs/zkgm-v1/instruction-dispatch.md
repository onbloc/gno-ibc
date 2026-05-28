# Instruction Dispatch

The implementation routes all instruction families through four dispatcher
helpers:

- `dispatchVerify`
- `dispatchExecute`
- `dispatchAck`
- `dispatchTimeout`

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
