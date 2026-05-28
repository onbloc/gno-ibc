# Domain Types

Core uses small wrapper types for protocol identifiers and wire values:

| Type | Underlying type | Notes |
|------|-----------------|-------|
| `ClientId` | `uint32` | Allocated by core. Starts at `1`. |
| `ConnectionId` | `uint32` | Allocated by core. Starts at `1`. |
| `ChannelId` | `uint32` | Allocated by core. Starts at `1`. |
| `ClientType` | `string` | Light-client registry key. |
| `Timestamp` | `uint64` | Unix time in nanoseconds. |
| `Height` | `uint64` | Chain height. |
| `Bytes` | `[]byte` | Used for port ids and byte-rendered fields. |
| `H256` | `[32]byte` | Keccak hash output and commitment value. |

Core defines `Status` for light-client lifecycle, `ConnectionState` and
`ChannelState` for handshake state machines, and `PacketStatus` for the value
returned by `OnRecvPacket`. The complete enum definitions and integer values
are in
[`gno.land/r/core/ibc/v1/core/types.gno`](../../../gno.land/r/core/ibc/v1/core/types.gno).

`ChannelState` includes a `ChannelStateClosed` value that is defined for
compatibility but unreachable in current execution, because channel close entry
points panic before mutating state.

Packets contain source channel, destination channel, data, timeout height, and
timeout timestamp.

> **Packet identity is the Keccak hash of the ABI-encoded packet, not a
> sequence number.** There is no `Sequence` field. Two packets that share the
> same channels, data, and timeout collide on this hash, and the second
> receive observes the existing receipt.

`Packet.TimeoutHeight` exists for ABI shape compatibility, but it must be
zero. Packet encoding panics if a non-zero timeout height is provided. Current
timeout logic uses `TimeoutTimestamp` exclusively.

## ABI Encoding

Core ABI encoding uses `gno.land/p/core/encoding/abi` and the same params-style
encoding flavor used by ZKGM wire bytes.

| Type | Encoded tuple |
|------|---------------|
| `Connection` | `uint8 state`, `uint32 clientId`, `uint32 counterpartyClientId`, `uint32 counterpartyConnectionId` |
| `Channel` | `uint8 state`, `uint32 connectionId`, `uint32 counterpartyChannelId`, `bytes counterpartyPortId`, `string version` |
| `Packet` | `uint32 sourceChannelId`, `uint32 destinationChannelId`, `bytes data`, `uint64 timeoutHeight`, `uint64 timeoutTimestamp` |

Packet commitments are derived as:

- `CommitPacket(packet) = CommitPackets([]Packet{packet})`
- `CommitPackets(packets) = keccak(encodeTopLevelDynamic(encodePacketArray(packets)))`
- `CommitAcks(acks) = mergeAck(keccak(encodeTopLevelDynamic(encodeBytesArray(acks))))`

`mergeAck` overwrites the first byte of the acknowledgement hash with the first
byte, `0x01`, of `COMMITMENT_MAGIC`. This allows the receipt store to
distinguish a bare receipt sentinel from a committed acknowledgement hash.
