# Event Catalog

This catalog lists the current repository event surface for IBC and ZKGM. Event
types and attributes are external observation points for relayers, indexers,
smoke tests, and runbooks.

## Scope

The current emitted event surface is owned by the IBC v1 core realm under
[gno.land/r/core/ibc/v1/core](../../gno.land/r/core/ibc/v1/core). ZKGM packet
activity is observed through these core events because ZKGM sends, receives,
acknowledges, and times out packets through IBC core.

Event attributes are emitted as string key/value pairs. Binary payloads are
lowercase `0x`-prefixed hex strings. Numeric identifiers are base-10 decimal
strings.

## Module Layout

Event constants and packet-side emit helpers live in core. Client and
connection events are emitted directly at entry points because their attribute
sets are short. Channel and packet events use helpers to keep larger attribute
sets consistent across call sites.

| File | Purpose |
|------|---------|
| [events.gno](../../gno.land/r/core/ibc/v1/core/events.gno) | Event constants and helpers for channel, batch, packet, ack, and timeout events. |
| [client.gno](../../gno.land/r/core/ibc/v1/core/client.gno) | Direct `chain.Emit` calls for `CreateClient` and `UpdateClient`. |
| [connection.gno](../../gno.land/r/core/ibc/v1/core/connection.gno) | Direct `chain.Emit` calls for the four `ConnectionOpen*` events. |
| [channel.gno](../../gno.land/r/core/ibc/v1/core/channel.gno) | Calls `emitChannelEvent` for the four `ChannelOpen*` events. |
| [packet.gno](../../gno.land/r/core/ibc/v1/core/packet.gno) | Calls packet emit helpers for send, receive, acknowledgement, timeout, and batch paths. |
| [core.gno](../../gno.land/r/core/ibc/v1/core/core.gno) | Defines `hexString`, `hexAttr`, and `h256String`. |
| [types.gno](../../gno.land/r/core/ibc/v1/core/types.gno) | Defines `String()` rendering for numeric ids, byte values, and hashes. |

## Stability Levels

| Level | Meaning |
|-------|---------|
| Stable | Relayers, runbooks, and indexers may depend on the event type and listed attributes. Changes should be treated as compatibility changes. |
| Operational | Useful for debugging or smoke tests, but consumers should verify behavior against the source before relying on long-term stability. |
| Defined, not emitted | Constants exist, but the current code does not emit the event. Do not use as an indexer contract. |

## Client Events

| Event type | Emitting entrypoint | Attributes | Stability | Notes |
|------------|---------------------|------------|-----------|-------|
| `CreateClient` | `CreateClient` | `client_id`, `client_type` | Stable | Emitted after adapter create succeeds and initial client and consensus state are saved. |
| `UpdateClient` | `UpdateClient`, `ForceUpdateClient` | `client_type`, `client_id`, `height` | Stable | `ForceUpdateClient` emits the same event type as a normal update after the deployer-only update succeeds. |

## Connection Events

| Event type | Emitting entrypoint | Attributes | Stability | Notes |
|------------|---------------------|------------|-----------|-------|
| `ConnectionOpenInit` | `ConnectionOpenInit` | `connection_id`, `client_id`, `counterparty_client_id` | Stable | Counterparty connection id is not known at init time. |
| `ConnectionOpenTry` | `ConnectionOpenTry` | `connection_id`, `client_id`, `counterparty_client_id`, `counterparty_connection_id` | Stable | Emitted after proof verification and local try-state save. |
| `ConnectionOpenAck` | `ConnectionOpenAck` | `connection_id`, `client_id`, `counterparty_client_id`, `counterparty_connection_id` | Stable | Emitted after proof verification and transition to open. |
| `ConnectionOpenConfirm` | `ConnectionOpenConfirm` | `connection_id`, `client_id`, `counterparty_client_id`, `counterparty_connection_id` | Stable | Emitted after proof verification and transition to open. |

## Channel Events

All channel events include:

- `port_id`
- `channel_id`
- `counterparty_port_id`
- `connection_id`
- `connection_client_id`
- `connection_counterparty_client_id`
- `connection_counterparty_connection_id`
- `version`

All channel events except `ChannelOpenInit` also include:

- `counterparty_channel_id`

`ChannelOpenInit` omits `counterparty_channel_id` because the counterparty
channel id is not known yet. This is the only conditional attribute omission in
the current event surface. Every other event emits its full listed attribute
set when it is emitted.

| Event type | Emitting entrypoint | Stability | Notes |
|------------|---------------------|-----------|-------|
| `ChannelOpenInit` | `ChannelOpenInit` | Stable | The counterparty channel id is intentionally omitted. |
| `ChannelOpenTry` | `ChannelOpenTry` | Stable | Includes the proposed counterparty channel id from the try-side channel state. |
| `ChannelOpenAck` | `ChannelOpenAck` | Stable | Emitted after acknowledgement proof verification and local channel open. |
| `ChannelOpenConfirm` | `ChannelOpenConfirm` | Stable | Emitted after confirm proof verification and local channel open. |

`ChannelCloseInit` and `ChannelCloseConfirm` constants exist in core, but the
current implementation does not emit them. The channel close entry points panic
as unsupported before any close event can be emitted.

## Batch Send Event

| Event type | Emitting entrypoint | Attributes | Stability | Notes |
|------------|---------------------|------------|-----------|-------|
| `BatchSend` | `BatchSend` | `batch_hash`, `source_channel_id`, `source_channel_version`, `source_connection_id`, `source_connection_client_id`, `destination_channel_id`, `destination_connection_id`, `destination_connection_client_id` | Stable | Emitted once for the batch before per-packet `PacketSend` events. It does not include `packet_hash`, `packet_data`, or `timeout_timestamp`. |

## Packet Events

Shared packet attributes:

- `packet_hash`: commitment hash for the packet
- `packet_data`: packet data as lowercase `0x`-prefixed hex
- `source_channel_id`
- `destination_channel_id`
- `timeout_timestamp`

Every event in the table below includes all shared packet attributes listed
above. Source-side events also include source channel or connection context.
Receive-side events include destination channel or connection context.

| Event type | Emitting entrypoint | Attributes in addition to shared packet attributes | Stability | Notes |
|------------|---------------------|-----------------------------------------------------|-----------|-------|
| `PacketSend` | `PacketSend` and per-packet emit in `BatchSend` | `source_channel_version`, `source_connection_id`, `source_connection_client_id`, `destination_connection_id`, `destination_connection_client_id` | Stable | Emitted once for a direct send and once per packet in a batch send. |
| `PacketRecv` | `PacketRecv` | `source_connection_id`, `source_connection_client_id`, `destination_channel_version`, `destination_connection_id`, `destination_connection_client_id`, `maker_msg` | Stable | `maker_msg` is the relayer message bytes as hex. Sync receives may also emit `WriteAck` in the same transaction. Async receives do not write the final ack immediately. |
| `IntentPacketRecv` | `IntentPacketRecv` | `source_connection_id`, `source_connection_client_id`, `destination_channel_version`, `destination_connection_id`, `destination_connection_client_id`, `market_maker_msg` | Operational | Intent receive path does not follow the normal proof and acknowledgement write flow. |
| `WriteAck` | `PacketRecv` for sync ack and `WriteAcknowledgement` for async ack | `source_connection_id`, `source_connection_client_id`, `destination_channel_version`, `destination_connection_id`, `destination_connection_client_id`, `acknowledgement` | Stable | `acknowledgement` is hex. Async ZKGM forward completion writes the parent ack through this event. |
| `PacketAck` | `PacketAcknowledgement` | `source_channel_version`, `source_connection_id`, `source_connection_client_id`, `destination_connection_id`, `destination_connection_client_id`, `acknowledgement` | Stable | Emitted after acknowledgement proof verification and source commitment deletion. |
| `PacketTimeout` | `PacketTimeout` | `source_channel_version`, `source_connection_id`, `source_connection_client_id`, `destination_connection_id`, `destination_connection_client_id` | Stable | Emitted after timeout proof verification and source commitment deletion. |

## ZKGM Event Surface

ZKGM currently relies on IBC core events for packet observation:

- sends are visible as `PacketSend` and, for batch sends, `BatchSend`
- receives are visible as `PacketRecv` and usually `WriteAck`
- async forward completion is visible as `WriteAck`
- acknowledgement handling is visible as `PacketAck`
- timeout handling is visible as `PacketTimeout`

The package
[gno.land/p/core/ibc/zkgm/events.gno](../../gno.land/p/core/ibc/zkgm/events.gno)
defines the following event constants, but the current code does not emit them:

| Event type | Attributes | Stability | Notes |
|------------|------------|-----------|-------|
| `zkgm_forward_child_ack` | `parent_sequence`, `child_sequence`, `parent_client`, `child_client`, `ack_hex` | Defined, not emitted | Reserved constant. Do not index against it because no emit path exists. |
| `zkgm_forward_child_timeout` | `parent_sequence`, `child_sequence`, `parent_client`, `child_client` | Defined, not emitted | Reserved constant. Do not index against it because no emit path exists. |

## Attribute Encoding

Binary event attributes use lowercase `0x`-prefixed hex. This applies to
`packet_data`, `acknowledgement`, `maker_msg`, and `market_maker_msg`.
`packet_hash` and `batch_hash` use the same `0x` hex rendering through `H256`.

Byte-valued identifiers also render as hex. For example, `port_id` is emitted
as the hex encoding of the port id bytes. For app realms, that value is usually
the UTF-8 bytes of the app realm package path. ZKGM's proxy `port_id` is
`0x676e6f2e6c616e642f722f676e6f737761702f6962632f76312f617070732f7a6b676d`,
which is the UTF-8 encoding of `gno.land/r/gnoswap/ibc/v1/apps/zkgm`.

Numeric ids and heights use base-10 decimal strings without a `0x` prefix. This
applies to `client_id`, `connection_id`, `channel_id`, `timeout_timestamp`, and
`height`. A channel id of `27` is emitted as `"27"`, not `"0x1B"` or a padded
hex value.

Attribute names are part of the indexer contract for stable events. Indexers
must match attributes by key rather than by position because attribute ordering
within an event is not a compatibility contract.

## Attribute Size Limit

The Gno chain enforces a 1024-character limit on each emitted event attribute
value. IBC core does not truncate or split event attributes before calling
`chain.Emit`. If an emitted value exceeds the chain limit, the runtime rejects
the emit.

For binary values encoded through `hexAttr`, the largest raw payload that fits
is 511 bytes. The `0x` prefix uses 2 characters and each raw byte uses 2 hex
characters.

Realistic ZKGM packets can exceed this limit. A representative ZKGM `Call`
packet with hundreds of bytes of calldata produces an encoded `packet_data`
attribute longer than 1024 characters. Indexers should not assume that ZKGM
packet content is always recoverable from the `packet_data` event attribute
alone. When full packet content is needed, reconstruct it from the source
transaction body.

## Emission Mechanics

Client and connection events are emitted inline at their entry points. Channel,
batch, packet, acknowledgement, and timeout events use shared helper paths so
their larger attribute sets stay consistent across call sites.

`ChannelOpenInit` is the only event whose helper conditionally omits an
attribute. It omits `counterparty_channel_id` instead of emitting an unset
numeric sentinel.

`PacketRecv` and `IntentPacketRecv` share the same receive-side attribute
shape. The final message attribute key differs by path: `PacketRecv` uses
`maker_msg`, while `IntentPacketRecv` uses `market_maker_msg`.

## Emission Timing

Every event is emitted after its underlying state mutation or callback
settlement. Indexers can treat an emitted event as confirmation that the
corresponding state change occurred.

| Event | Emitted after |
|-------|---------------|
| `CreateClient` | Adapter create succeeds and core saves initial client and consensus state. |
| `UpdateClient` | Adapter update returns and core persists the new client and consensus state. |
| `ConnectionOpen*` | Core saves the new connection state. |
| `ChannelOpen*` | Core saves the channel state and invokes the app callback. |
| `BatchSend` | Core writes the batch commitment and per-packet in-memory commitments. |
| `PacketSend` | Core writes the packet commitment. |
| `PacketRecv` | Core saves the receipt and dispatches the app receive callback. |
| `WriteAck` | Core commits the acknowledgement. |
| `PacketAck` | Core deletes the source commitment after the app ack callback. |
| `PacketTimeout` | Core deletes the source commitment after the app timeout callback. |

Within a single transaction, helper-emitted events appear in helper call order.
A `BatchSend` event always precedes the per-packet `PacketSend` events it
generates. Across transactions, consumers should use block height and
transaction order from the chain or indexer.

## Implementation Differences

| Area | Current behavior |
|------|------------------|
| Encoding | Binary attributes use lowercase `0x` hex. Numeric ids use base-10 decimal. |
| Attribute size | The 1024-character limit is enforced by the chain runtime, not by IBC core. |
| Ordering within a transaction | Helper-emitted events appear in the order their helpers are called. |
| Ordering across transactions | Consumers should use block height and transaction order from the chain or indexer. |
| Unemitted constants | `ChannelCloseInit`, `ChannelCloseConfirm`, `zkgm_forward_child_ack`, and `zkgm_forward_child_timeout` exist but no code emits them. |
| Conditional attributes | Only `ChannelOpenInit` omits `counterparty_channel_id`. |
| Attribute keys | Stable event attribute keys are compatibility surface. |
| Attribute ordering | Consumers should filter by attribute key, not position. |

Query examples and tx-indexer filtering caveats are documented in
[docs/tx-indexer.md](../tx-indexer.md).
