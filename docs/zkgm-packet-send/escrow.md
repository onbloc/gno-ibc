# TokenOrderV2 ESCROW Send

Use `ESCROW` for later sends of a native token after the corresponding `INITIALIZE` has created the wrapped token on Union.

The 2026-05-20 ugnot `ESCROW` at block 93 followed this variant. See the worked example at the end of this page for the recorded send.

## Required Inputs

`ESCROW` does not need `TokenMetadata`, the `ZkgmERC20` implementation address, initializer calldata, authority, token name, token symbol, or decimals.

Collect:

| Input | Source | Notes |
|---|---|---|
| Destination channel id | Union | EVM-side channel paired with the Gno source channel |
| Receiver EOA | Union | Goes into `TokenOrderV2.Receiver` as 20 raw bytes |
| Base token denom | Shared | Example: `ugnot` |
| Base amount | Shared | Base units only; must match `-send` |
| Quote amount | Shared | Usually equal to `BaseAmount` |
| Wrapped token address | Prior `INITIALIZE` / Union | Goes into `TokenOrderV2.QuoteToken` as 20 raw bytes |

## Differences from INITIALIZE

| Aspect | `INITIALIZE` | `ESCROW` |
|---|---|---|
| `Kind` | `0` (`TOKEN_ORDER_KIND_INITIALIZE`) | `1` (`TOKEN_ORDER_KIND_ESCROW`) |
| `Metadata` | `EncodeTokenMetadata(TokenMetadata)` | empty bytes |
| `QuoteToken` | predicted address for a token that does not exist yet | the wrapped token address the earlier `INITIALIZE` already created |
| Implementation, Initializer, authority, name, symbol, decimals | required | not used |
| `predictWrappedTokenV2` call | run it to obtain `QuoteToken` | skip it, reuse the known address |

Send-side validation is identical for both kinds. `verifyTokenOrderV2` runs the same rate-limit, `requireSentCoin`, and `increaseChannelBalanceV2` path, so `-send` must still match `BaseAmount` exactly.

## Operand

The `ESCROW` operand uses the same `TokenOrderV2Schema` as `INITIALIZE`:

| TokenOrderV2 field | Value | Encoding note |
|---|---|---|
| `Sender` | Gno sender address | ASCII bytes, e.g. `[]byte("g1...")` |
| `Receiver` | Union EOA | 20 raw address bytes, not ASCII `"0x..."` |
| `BaseToken` | Native denom | ASCII bytes, e.g. `[]byte("ugnot")` |
| `BaseAmount` | Sent native amount | uint256; must match `-send` amount exactly |
| `QuoteToken` | Existing wrapped token | 20 raw address bytes, not ASCII `"0x..."` |
| `QuoteAmount` | Receiver amount | uint256 |
| `Kind` | `TOKEN_ORDER_KIND_ESCROW` | `1` |
| `Metadata` | Empty bytes | dynamic bytes field of length `0` |

Use the ZKGM wire ABI flavor: `abi_encode_params`, not plain Solidity `abi.encode`.

A ugnot `ESCROW` for `1000000` ugnot with `QuoteToken` `0x4271Eb8F0243F1E1F303912841fdcE55c06CF223` and a placeholder receiver `0x<RECEIVER_EOA>` encodes to:

```text
0000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000016000000000000000000000000000000000000000000000000000000000000001a000000000000000000000000000000000000000000000000000000000000f424000000000000000000000000000000000000000000000000000000000000001e000000000000000000000000000000000000000000000000000000000000f424000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000220000000000000000000000000000000000000000000000000000000000000002867316a67386d74757475396b6868667763346e786d756863706674663070616a64686676737166350000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000014eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee000000000000000000000000000000000000000000000000000000000000000000000000000000000000000575676e6f7400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000144271eb8f0243f1e1f303912841fdce55c06cf2230000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
```

The 20-byte receiver region is the repeated `ee` placeholder. Replace it with Union's real receiver address before broadcasting.

## Recv-side Precondition

An `ESCROW` is valid only if the wrapped token already exists on Union. The recv path looks up the stored metadata image for `QuoteToken` and checks:

```text
QuoteToken == predictWrappedTokenV2(path, destChannel, baseToken, storedImage)
```

If the preceding `INITIALIZE` has not been processed on Union, the recv path has no stored image and falls back to the V1 prediction, which does not match the V2 `QuoteToken` we sent. The `ESCROW` then fails recv with `universal_error_ack`.

Confirm the `INITIALIZE` was acknowledged before broadcasting an `ESCROW` against it.

## Broadcast

Regenerate `SALT` and `TIMEOUT` for every send. A reused salt produces a duplicate packet that the chain rejects.

```bash
SALT="$(openssl rand -hex 32)"
TIMEOUT="$(python3 -c 'import time; print(int((time.time()+3600)*1_000_000_000))')"
OPERAND="<ESCROW operand hex from the section above>"

printf '\n' | gnokey maketx call \
  -insecure-password-stdin \
  -pkgpath "gno.land/r/gnoswap/ibc/v1/apps/zkgm" \
  -func "SendRaw" \
  -args "1" \
  -args "$TIMEOUT" \
  -args "$SALT" \
  -args "2" \
  -args "3" \
  -args "$OPERAND" \
  -gas-fee "5000000ugnot" \
  -gas-wanted "200000000" \
  -send "1000000ugnot" \
  -broadcast \
  -remote "http://23.20.153.250:26657" \
  -chainid "dev" \
  test1
```

The `-send` amount must equal `BaseAmount`. See [Common SendRaw Procedure](common.md) for argument mapping, verification, handoff, and operational hazards.

## Worked Example

The 2026-05-20 ugnot `ESCROW` at block 93 produced:

| Field | Value |
|---|---|
| SALT | `76b58111b86ceef62d9a717109d6b9e60665b569113bb2fe2ffb95418b639b40` |
| TIMEOUT | `1779216878664781056` |
| Block height | `93` |
| GAS USED | `42649471` |
| TX hash (hex) | `86223e0e4bd55a3eaf50bb968c64d69a6131ee80fbcdf3b75932bb27ec3cd8d9` |
| TX hash (base64) | `hiI+DkvVWj6vULuWjGTWmmEx7oD7zfO3WTK7J+w82Nk=` |
| packet_hash | `0x9acadd5666ca5905c353ff9c8306ec6063d6ec2b86b530f9921352089507cad0` |
| source / destination channel | `1` / `25` |

This run used Union's real receiver address. The `packet_hash` above does not match a packet encoded with the placeholder receiver shown in the Operand section.
