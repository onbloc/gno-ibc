# Wire Encoding

ZKGM wire bytes are produced by the `gno.land/p/core/encoding/abi` package.
The package implements Solidity's params tuple form, equivalent to
`abi_encode_params` in solc terminology. Each top-level tuple has a head of
fixed-size slots followed by a tail of dynamic-field data. Plain
`abi.encode` (which omits the outer offset for single dynamic top-level values)
is not used.

The encoding is deterministic. Given the same instruction tree, the same path,
and the same salt, the encoder produces identical bytes on every call.

### Encoding invariants

| Invariant | Notes |
|-----------|-------|
| ABI flavor | Solidity params tuple. Plain top-level `abi.encode` is not produced or accepted. |
| Word size | 32 bytes (256 bits). |
| Numeric layout | `uintN` values are big-endian and right-aligned in their 32-byte word. `uint8 Opcode` lives in byte 31 of its slot. |
| Dynamic layout | Each dynamic field reserves a single 32-byte head slot holding a byte offset into the tail. The tail entry begins with a 32-byte length word followed by the value bytes padded to a 32-byte boundary. |
| Salt | Exactly 32 bytes. `SendRaw` rejects any other hex length. |
| Instruction version | `Instruction.Version` must equal `INSTR_VERSION_2` for `OP_TOKEN_ORDER` and `INSTR_VERSION_0` for `OP_FORWARD`, `OP_CALL`, and `OP_BATCH`. The dispatcher rejects any other combination. |
| Path packing | `*u256.Uint`. Channel ids occupy 32-bit slots packed LSB-first. The next hop to dequeue lives in the lowest 32 bits. The maximum is 8 hops. |
| `ACK_ERR_ONLY_MAKER` | The literal 4-byte marker `0xDE 0xAD 0xC0 0xDE` placed verbatim inside `Ack.InnerAck`. The outer `Ack.Tag` is still `TAG_ACK_SUCCESS` when this marker is used. |
| Forward salt marker | `DeriveForwardSalt` OR-masks `FORWARD_SALT_MAGIC` into the salt so `IsForwardedPacket` can distinguish forwarded child packets at ack and timeout time. |

### Envelope layouts

The following diagrams use the convention from RFC 791 and RFC 793: a top
ruler marks byte positions inside each row, and each row corresponds to one
32-byte ABI word. Dynamic-field tails are drawn with `/` borders.

**ZkgmPacket** (3-slot head + dynamic Instruction tail):

```text
                    1                   2                   3
0  1  2  3  4  5  6  7  8  9  0  1  2  3  4  5  6  7  8  9  0  1  2  3  4  5  6  7  8  9  0  1
+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
|                                       Salt (bytes32)                                          |
+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
|                              Path (uint256, packed channel ids)                               |
+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
|                              Offset to Instruction tail (= 0x60)                              |
+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
/                                    Instruction (dynamic)                                     /
+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
```

**Instruction** (3-slot head + dynamic Operand tail):

```text
+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
|                          padding (31 bytes)                          |   Version (uint8)     |
+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
|                          padding (31 bytes)                          |    Opcode (uint8)     |
+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
|                                Offset to Operand tail (= 0x60)                                |
+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
|                                 Operand length (uint256)                                      |
+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
/                       Operand bytes (padded to 32-byte boundary)                              /
+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
```

`Operand` is the ABI encoding of the per-opcode operand struct.

### Per-opcode operand structures

```go
type Forward struct {
    Path             *u256.Uint
    TimeoutHeight    uint64
    TimeoutTimestamp uint64
    Instruction      Instruction
}

type Call struct {
    Sender           []byte
    Eureka           bool
    ContractAddress  []byte
    ContractCalldata []byte
}

type Batch struct {
    Instructions []Instruction
}

type TokenOrderV2 struct {
    Sender      []byte
    Receiver    []byte
    BaseToken   []byte
    BaseAmount  *u256.Uint
    QuoteToken  []byte
    QuoteAmount *u256.Uint
    Kind        uint8
    Metadata    []byte
}
```

`TokenOrderV1` remains in the ABI package for legacy decoding and fixtures, but
the current token-order handler uses `TokenOrderV2`.

### Acknowledgement envelopes

```go
type Ack struct {
    Tag      *u256.Uint
    InnerAck []byte
}

type BatchAck struct {
    Acknowledgements [][]byte
}

type TokenOrderAck struct {
    FillType    *u256.Uint
    MarketMaker []byte
}
```

`Ack` head layout (2-slot head + dynamic InnerAck tail):

```text
+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
|                                       Tag (uint256)                                           |
+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
|                                Offset to InnerAck tail (= 0x40)                               |
+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
|                                 InnerAck length (uint256)                                     |
+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
/                       InnerAck bytes (padded to 32-byte boundary)                             /
+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
```

### Tag, FillType, and salt-marker constants

`Tag` and `FillType` occupy 32-byte slots. Most of the slot is zero, with a
short marker at a known byte position. The `0x00...` ellipsis in the table
below stands for the zero padding needed to fill the slot to 32 bytes total.

| Constant | 32-byte shape | Marker | Role |
|----------|---------------|--------|------|
| `TAG_ACK_FAILURE` | `0x00...00` | all zero | failure outer `Ack.Tag` |
| `TAG_ACK_SUCCESS` | `0x00...0001` | last byte = `0x01` | success outer `Ack.Tag` |
| `FILL_TYPE_PROTOCOL` | `0x00...00b0cad0` | last 3 bytes = `0xb0cad0` | protocol-fill `TokenOrderAck.FillType` |
| `FILL_TYPE_MARKETMAKER` | `0x00...d1cec45e` | last 4 bytes = `0xd1cec45e` | market-maker-fill `TokenOrderAck.FillType` |
| `FORWARD_SALT_MAGIC` | `0xc0de...babe` | first 2 bytes = `0xc0de`, last 2 bytes = `0xbabe` | OR-masked into forwarded child salt so `IsForwardedPacket` can detect it |

`ACK_ERR_ONLY_MAKER` is a 4-byte marker (not a 32-byte slot). It is placed
verbatim inside `Ack.InnerAck` while `Ack.Tag` stays `TAG_ACK_SUCCESS`:

| Constant | Bytes | Placement |
|----------|-------|-----------|
| `ACK_ERR_ONLY_MAKER` | `0xdeadc0de` | inside `Ack.InnerAck`, outer `Tag` remains success |

### Path layout (uint256, packed channel ids, LSB-first)

`Path` packs up to 8 channel ids into a single `uint256`. Each id occupies one
32-bit slot. Slot 0 holds the next hop to be dequeued.

| Property | Value |
|----------|-------|
| Container | `uint256` (32 bytes, big-endian) |
| Slot width | 32 bits per channel id |
| Slot count | 8 (one per IBC hop) |
| Slot 0 location | lowest 32 bits, bytes 28-31 |
| Slot 7 location | highest 32 bits, bytes 0-3 |
| Dequeue | `DequeueChannelFromPath` returns slot 0 and right-shifts the path by 32 bits |
| Append | `UpdateChannelPath` writes into the lowest free high-order slot |
| Overflow | Encoding panics when all 8 slots are occupied |

Slot order (high-order bytes on the left, low-order on the right):

```text
slot:    7        6        5        4        3        2        1        0
bytes:  0-3      4-7      8-11     12-15    16-19    20-23    24-27    28-31
                                                                       ^^^^^^
                                                                       next hop
```
