# Store Layout and Commitments

<!--
TODO(#39): commit keys are hex-rendered solely because `chain/params`
currently accepts only string keys. When the params API accepts raw byte
keys, `commit` will write the 32-byte path directly (prefix++raw) and the
"lowercase, 0x-prefixed hex rendering" wording in the paragraph below
becomes obsolete.

TODO(#43): once `chain/params` exposes a reader (e.g. `params.GetBytes`),
the `batchPackets` and `batchReceipts` in-memory mirrors are removed. After
that, the "two views" framing collapses to a single params-backed store for
those entries, and the matching rows in the in-memory table should be
dropped (their values live only in the params store).
-->

Core keeps two views of committed state:

- in-memory maps inside the package-level `State` struct, used by core logic
- chain `params` commitments, used by counterparty light clients

Every `params` commitment key is a lowercase, `0x`-prefixed hex rendering
(`H256.String()`) of a 32-byte path. Every commitment value is 32 bytes. The
`commit` helper writes those values through `params.SetBytes`.

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

Each path helper hashes the 32-byte namespace constant followed by 32-byte
big-endian id, height, or hash words. For example,
`ConsensusStatePath(clientId, height)` keccak-hashes
`CONSENSUS_STATE || clientId_as_32_bytes || height_as_32_bytes`.

Sentinel and value catalogue for the receipt store:

| Value | Meaning |
|-------|---------|
| (missing key) | No receipt has been recorded for the packet. |
| `COMMITMENT_MAGIC_ACK` | Receipt exists; no application acknowledgement has been committed yet. |
| any other 32-byte value | Committed acknowledgement hash from `CommitAcks(...)`. |

`COMMITMENT_MAGIC` itself is used in the packet store (a pending outgoing
packet or batch commitment), not the receipt store.

Committed acknowledgement values pass through `mergeAck`, which rewrites the
first byte to match `COMMITMENT_MAGIC[0] = 0x01`. This lets a reader
distinguish the bare receipt sentinel (`COMMITMENT_MAGIC_ACK[0] = 0x02`) from
an actual ack hash by inspecting one byte.
