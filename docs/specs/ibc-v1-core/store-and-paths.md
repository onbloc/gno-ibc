# Store Layout and Commitments

Core keeps two views of committed state:

- in-memory maps inside the package-level `State` struct, used by core logic
- chain `params` commitments, used by counterparty light clients

Every `params` commitment key is a hex-encoded 32-byte path, and every
commitment value is 32 bytes. The `commit` helper writes those values through
`params.SetBytes`.

Major in-memory stores:

| Store | Key | Value |
|-------|-----|-------|
| `clientRegistry` | `ClientType` | light-client adapter |
| `clientTypes` | `ClientId` | `ClientType` |
| `clientStates` | `ClientId` | encoded client state bytes |
| `consensusStates` | `ClientId`, `Height` | encoded consensus state bytes |
| `connections` | `ConnectionId` | `Connection` |
| `channels` | `ChannelId` | `Channel` |
| `ports` | port id string | app implementation |
| `channelOwners` | `ChannelId` | port id bytes |
| `batchPackets` | derived packet or batch path | `H256` commitment value |
| `batchReceipts` | derived receipt or ack path | `H256` receipt sentinel or ack hash |

Path namespaces:

| Namespace | Last byte | Used by |
|-----------|-----------|---------|
| `CLIENT_STATE` | `0x00` | `ClientStatePath` |
| `CONSENSUS_STATE` | `0x01` | `ConsensusStatePath` |
| `CONNECTIONS` | `0x02` | `ConnectionPath` |
| `CHANNELS` | `0x03` | `ChannelPath` |
| `PACKETS` | `0x04` | `BatchPacketsPath`, `PacketCommitmentPath` |
| `PACKET_ACKS` | `0x05` | `BatchReceiptsPath`, `PacketAcknowledgementPath` |

Path helpers use Keccak over the namespace plus right-aligned 32-byte
big-endian numeric ids or hashes. For example,
`ConsensusStatePath(clientId, height)` hashes the consensus-state namespace,
`clientId`, and `height`.

Sentinel values:

| Sentinel | Meaning |
|----------|---------|
| `COMMITMENT_MAGIC` | Pending outgoing packet or batch commitment |
| `COMMITMENT_MAGIC_ACK` | Bare receipt with no application acknowledgement |

Missing receipt state means no receipt. `COMMITMENT_MAGIC_ACK` means a packet
was received but no acknowledgement hash has been committed. Any value other
than `COMMITMENT_MAGIC_ACK` in the receipt store is treated as an
acknowledgement hash.

Committed acknowledgement values are not sentinels. They are
`CommitAcks(...)` hashes. `CommitAcks(...)` uses `mergeAck`, so committed
acknowledgement hashes start with the same first byte as `COMMITMENT_MAGIC`.
