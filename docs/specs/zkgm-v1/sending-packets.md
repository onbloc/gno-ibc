# Sending Packets

`Send` accepts a typed `z.Instruction`:

```go
func Send(
    cur realm,
    channelId core.ChannelId,
    timeoutTimestamp core.Timestamp,
    salt [32]byte,
    instruction z.Instruction,
) core.Packet
```

`SendRaw` accepts primitive fields for `gnokey maketx call`:

```go
func SendRaw(
    cur realm,
    channelId uint32,
    timeoutTimestamp uint64,
    saltHex string,
    version uint8,
    opcode uint8,
    operandHex string,
) core.Packet
```

`SendRaw` strips an optional `0x` prefix from hex arguments, requires a
32-byte salt, decodes the operand, constructs an instruction, and uses the same
send path as `Send`.

The shared send path rejects paused or uninitialized proxy state, calls
`impl.Send` with a `SendRequest`, and forwards the returned ZKGM packet bytes
to `core.PacketSend`. The ZKGM proxy realm is the port owner for the source
channel, so IBC core accepts the send and writes the packet commitment.

Example emission:

```json
{
  "type": "PacketSend",
  "attrs": [
    {
      "key": "packet_hash",
      "value": "0x0000...000000"
    },
    {
      "key": "packet_data",
      "value": "0x0000...01030801..."
    },
    {
      "key": "source_channel_id",
      "value": "1"
    },
    {
      "key": "source_channel_version",
      "value": "ucs03-zkgm-0"
    },
    {
      "key": "source_connection_id",
      "value": "1"
    },
    {
      "key": "source_connection_client_id",
      "value": "1"
    },
    {
      "key": "destination_channel_id",
      "value": "27"
    },
    {
      "key": "destination_connection_id",
      "value": "3"
    },
    {
      "key": "destination_connection_client_id",
      "value": "7"
    },
    {
      "key": "timeout_timestamp",
      "value": "1750000000000000000"
    }
  ],
  "pkg_path": "gno.land/r/core/ibc/v1/core"
}
```

The `packet_data` value is the hex encoding of an ABI-encoded `ZkgmPacket`
envelope. Realistic ZKGM packets can exceed the 1024-character event attribute
limit, so indexers reconstruct the full packet from the transaction body rather
than from the event. See [Event Catalog](../events.md) for the limit.

`impl.Send` verifies the instruction against the raw user salt. The wire packet
then uses `DeriveSenderSalt(sender, salt)` and starts with `Path = 0`.

Native-token sends require a direct `gnokey maketx call` transaction. A
`maketx run` script changes the previous realm to the script realm, so
`IsUserCall()` is false and attached native coins are not captured as
`SentCoins`.
