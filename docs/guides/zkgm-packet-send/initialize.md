# TokenOrderV2 INITIALIZE Send

Use `INITIALIZE` only for the first native-token send over a channel. It carries
the `TokenMetadata` that creates the wrapped token on Union.

The original worked example below targets EVM Union. For CosmWasm Union, use
the platform-specific values in the next section instead of EVM addresses and
Solidity initializer calldata.

## CosmWasm Union

The local `union-devnet-1` E2E path uses CW20 metadata:

- `Receiver` and `QuoteToken` are the ASCII bytes of their `union1...` Bech32
  addresses, not raw 20-byte EVM addresses.
- `Implementation` is the JSON bytes of
  `{"admin":"<zkgm-admin>","code_id":<cw20-code-id>}`.
- `Initializer` is the JSON bytes of the frissitheto CW20 init message:

```json
{
  "init": {
    "name": "<name>",
    "symbol": "<symbol>",
    "decimals": 6,
    "initial_balances": [],
    "mint": {
      "minter": "<token-minter-address>",
      "cap": null
    },
    "marketing": null
  }
}
```

ABI-encode those two byte arrays as `TokenMetadata`, compute
`keccak256(metadata)`, and query the destination ZKGM contract with
`predict_wrapped_token_v2` using the packet path, destination channel, base
token bytes, and metadata hash. Put the returned `wrapped_token` Bech32 string
into `QuoteToken` as ASCII bytes.

The successful local PacketSend → Recv → Ack run used this format. An EVM
initializer selector or a raw 20-byte receiver produces an invalid CosmWasm
operand.

## EVM Union

The 2026-05-20 ugnot `INITIALIZE` at block 63 followed this procedure.

## Required Inputs

Before encoding or broadcasting anything, collect these inputs from Union. Treat
any missing field as a blocker unless a placeholder send was explicitly
approved.

| Input | Source | Notes |
|---|---|---|
| Destination channel id | Union | EVM-side channel paired with the Gno source channel |
| EVM ZKGM contract address | Union | Used inside initializer calldata |
| `ZkgmERC20` implementation address | Union | Used in `TokenMetadata.Implementation` |
| Authority EOA | Union | Used as both `authority` and `Receiver` |
| Token name, symbol, decimals | Union | Encoded inside initializer calldata |
| Base token denom | Shared | Example: `ugnot` |
| Base amount | Shared | Base units only |
| Quote amount | Shared | Usually equal to `BaseAmount` |
| Predicted `quote_token` | Union | Output of `predictWrappedTokenV2` |

## Encode the Operand

`gnokey maketx call` cannot pass nested Gno structs directly. Encode the
`TokenOrderV2` operand ahead of time and pass it into
`SendRaw(operandHex string)`.

Use the ZKGM wire ABI flavor: `abi_encode_params`, not plain Solidity `abi.encode`.

Plain `abi.encode` treats the struct as one dynamic function argument and
prepends an extra 32-byte head offset. Union's ZKGM wire format uses the
`_params` flavor, where the struct fields are encoded as the top-level tuple.
In this repo, prefer `z.EncodeTokenOrderV2` and `z.EncodeTokenMetadata` from
the module import path `gno.land/p/onbloc/ibc/union/zkgm` (source tree:
`gno.land/p/onbloc/ibc/union/zkgm`).

Field mapping for native-token `INITIALIZE`:

| TokenOrderV2 field | Value | Encoding note |
|---|---|---|
| `Sender` | Gno sender address | ASCII bytes, e.g. `[]byte("g1...")` |
| `Receiver` | Union EOA | 20 raw address bytes, not ASCII `"0x..."` |
| `BaseToken` | Native denom | ASCII bytes, e.g. `[]byte("ugnot")` |
| `BaseAmount` | Sent native amount | uint256; must match `-send` amount exactly |
| `QuoteToken` | Predicted wrapped token | 20 raw address bytes returned by `predictWrappedTokenV2`, not ASCII `"0x..."` |
| `QuoteAmount` | Receiver amount | uint256 |
| `Kind` | `TOKEN_ORDER_KIND_INITIALIZE` | `0` |
| `Metadata` | `EncodeTokenMetadata(TokenMetadata)` | ABI `_params` bytes |

`TokenMetadata` only contains:

```go
{
    Implementation []byte,
    Initializer    []byte,
}
```

Name, symbol, and decimals belong inside initializer calldata.

`Initializer` contains Solidity calldata for:

```solidity
initialize(address authority, address zkgm, string name, string symbol, uint8 decimals)
```

The correct selector is:

```text
0x8420ce99
```

Verify the selector locally:

```bash
cast sig 'initialize(address,address,string,string,uint8)'
```

The typo `initializer(...)` resolves to `0xd0f68ee2` and silently fails on the
recv side.

When writing an external encoder:

- Strip `0x` from EVM addresses and decode them into 20 bytes.
- Decode calldata hex into bytes before assigning `TokenMetadata.Initializer`.
- Encode `TokenMetadata` first, then put those encoded bytes in `TokenOrderV2.Metadata`.
- Encode the final `TokenOrderV2` with the `_params` flavor.

## Compute Predicted `quote_token`

The recv side validates `quote_token` against the result of `predictWrappedTokenV2(...)`.

Any mismatch causes the packet to fail during recv with `universal_error_ack`,
even if the packet itself was successfully relayed.

Example:

```bash
cast call <zkgm-evm-contract> \
  "predictWrappedTokenV2(uint256,uint32,bytes,tuple(bytes,bytes))(address,bytes32)" \
  <path> <destChannel> <baseTokenHex> \
  "(<implementationHex>,<initializerHex>)" \
  --rpc-url <evm-rpc>
```

Example result:

```text
0x4271Eb8F0243F1E1F303912841fdcE55c06CF223
```

Put the 20 raw returned address bytes into `TokenOrderV2.QuoteToken`. Do not
encode the printable `0x...` string as bytes.

Any change to implementation, initializer, or destination channel changes the
predicted address.

## Broadcast and Verify

Use [Common SendRaw Procedure](common.md) after `OPERAND` is ready.

## Worked Example

The 2026-05-20 ugnot `INITIALIZE` at block 63 produced:

| Field | Value |
|---|---|
| SALT | `aa12a2b0fb01b55f0a2ef7f7edf7ea721183548751bb979662cfce4e7c5827bc` |
| TIMEOUT | `1779206995211200000` |
| Block height | `63` |
| GAS USED | `51552539` |
| TX hash (hex) | `a232d013423ab9bccec3fefe6e40aa6b01668058132852e7a87b2aafb2058f0a` |
| TX hash (base64) | `ojLQE0I6ubzOw/7+bkCqawFmgFgTKFLnqHsqr7IFjwo=` |
| packet_hash | `0xf154b69d6ca569c9054f3c593f75bb9a4f1484e2c4fd0af3f8bde494a275e8fa` |
| Implementation | `0xAf739F34ddF951cBC24fdbBa4f76213688E13627` |
| quote_token | `0x4271Eb8F0243F1E1F303912841fdcE55c06CF223` |
| source / destination channel | `1` / `25` |

This is the corrected final send. Two earlier diagnostic sends used a placeholder Implementation or an empty `quote_token` and were superseded.
