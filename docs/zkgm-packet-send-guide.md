# ZKGM Packet Send Guide

This guide collects the operational procedure for broadcasting ZKGM `TokenOrderV2`
packets from the Gno side when requested by the Union team.

Start here to choose the correct send kind, then use the per-kind page to build
the operand and the common page to broadcast and verify the packet.

## Documents

| Document | Use when |
|---|---|
| [Common SendRaw Procedure](zkgm-packet-send/common.md) | You need the shared `SendRaw` command, broadcast verification, handoff checklist, and operational hazards. |
| [TokenOrderV2 INITIALIZE](zkgm-packet-send/initialize.md) | You are sending a native token for the first time over a channel and must create the wrapped token on Union. |
| [TokenOrderV2 ESCROW](zkgm-packet-send/escrow.md) | The wrapped token already exists on Union and you are sending a later native-token transfer over the same channel. |

## Current Testnet Reference

| Item | Value |
|---|---|
| Source code | `gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/` |
| Deployed pkgpath (testnet) | `gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm` |
| Wire ABI schemas | `gno.land/p/onbloc/ibc/union/zkgm/abi.gno` |
| Module import path | `gno.land/p/onbloc/ibc/union/zkgm` |
| RPC | `http://23.20.153.250:26657` |
| tx-indexer | `http://23.20.153.250:8546/graphql` |
| Gno channel id | `1` |
| Union channel id | `25` |

If the chain has been reset since this document was written, verify the current
channel state from a recent `ChannelOpenAck` event before broadcasting.

## Choosing the Send Kind

Use `INITIALIZE` for the first native-token send over a channel. This creates
the wrapped token on Union. It carries `TokenMetadata`, requires Union's
`ZkgmERC20` implementation address, and must use the predicted `quote_token`.

Use `ESCROW` for later sends of the same native token over the same channel
after the `INITIALIZE` has been processed on Union. It reuses the known wrapped
token address and carries empty metadata.

Both kinds use:

```text
version = 2
opcode  = 3
```

See [Common SendRaw Procedure](zkgm-packet-send/common.md) before broadcasting.
