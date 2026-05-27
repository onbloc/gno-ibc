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
lowercase `0x`-prefixed hex strings.

## Stability Levels

| Level | Meaning |
|-------|---------|
| Stable | Relayers, runbooks, and indexers may depend on the event type and listed attributes. Changes should be treated as compatibility changes. |
| Operational | Useful for debugging or smoke tests, but consumers should verify behavior against the source before relying on long-term stability. |
| Defined, not emitted | Constants exist, but the current code does not emit the event. Do not use as an indexer contract. |

## Client Events

| Event type | Emitting entrypoint | Attributes | Stability | Notes |
|------------|---------------------|------------|-----------|-------|
| `CreateClient` | `CreateClient` | `client_id`, `client_type` | Stable | Emitted after adapter create succeeds and initial client/consensus state is saved. |
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

| Event type | Emitting entrypoint | Stability | Notes |
|------------|---------------------|-----------|-------|
| `ChannelOpenInit` | `ChannelOpenInit` | Stable | The counterparty channel id is not known yet and is intentionally omitted. |
| `ChannelOpenTry` | `ChannelOpenTry` | Stable | Includes the proposed counterparty channel id from the try-side channel state. |
| `ChannelOpenAck` | `ChannelOpenAck` | Stable | Emitted after acknowledgement proof verification and local channel open. |
| `ChannelOpenConfirm` | `ChannelOpenConfirm` | Stable | Emitted after confirm proof verification and local channel open. |

`ChannelCloseInit` and `ChannelCloseConfirm` constants exist in core, but the
current implementation does not emit them.

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
| `PacketSend` | `PacketSend`; per-packet emit in `BatchSend` | `source_channel_version`, `source_connection_id`, `source_connection_client_id`, `destination_connection_id`, `destination_connection_client_id` | Stable | Emitted once for a direct send and once per packet in a batch send. |
| `PacketRecv` | `PacketRecv` | `source_connection_id`, `source_connection_client_id`, `destination_channel_version`, `destination_connection_id`, `destination_connection_client_id`, `maker_msg` | Stable | `maker_msg` is the relayer message bytes as hex. Sync receives may also emit `WriteAck` in the same transaction. Async receives do not write the final ack immediately. |
| `IntentPacketRecv` | `IntentPacketRecv` | `source_connection_id`, `source_connection_client_id`, `destination_channel_version`, `destination_connection_id`, `destination_connection_client_id`, `market_maker_msg` | Operational | Intent receive path does not follow the normal proof and acknowledgement write flow. |
| `WriteAck` | `PacketRecv` for sync ack; `WriteAcknowledgement` for async ack | `source_connection_id`, `source_connection_client_id`, `destination_channel_version`, `destination_connection_id`, `destination_connection_client_id`, `acknowledgement` | Stable | `acknowledgement` is hex. Async ZKGM forward completion writes the parent ack through this event. |
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
| `zkgm_forward_child_ack` | `parent_sequence`, `child_sequence`, `parent_client`, `child_client`, `ack_hex` | Defined, not emitted | Reserved constant; do not index against it until an emit path exists. |
| `zkgm_forward_child_timeout` | `parent_sequence`, `child_sequence`, `parent_client`, `child_client` | Defined, not emitted | Reserved constant; do not index against it until an emit path exists. |

## Encoding Rules

- Binary event attributes use lowercase `0x`-prefixed hex.
- Do not convert arbitrary packet data, acknowledgements, proofs, or messages to
  plain strings for event attributes.
- Attribute names are part of the indexer contract for stable events.
- Query examples and tx-indexer filtering caveats are documented in
  [docs/tx-indexer.md](../tx-indexer.md).
