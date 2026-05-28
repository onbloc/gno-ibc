# TokenOrderV2

`TokenOrderV2` handles native and voucher token movement. It defines four
kinds: `INITIALIZE`, `ESCROW`, `UNESCROW`, and `SOLVE`. The first three are
implemented; `SOLVE` is reserved.

## INITIALIZE

**Verify.** Charges the rate-limit bucket for `BaseToken`, requires the
sender to provide or burn `BaseAmount`, validates the predicted V2 quote
denom, and increases the channel balance. Native tokens must exactly match
the attached `SentCoins`. Wrapped `ibc/` base denoms are burned from the
sender.

**Execute.** Requires non-empty metadata, decodes `TokenMetadata`, computes
`MetadataImage`, predicts the wrapped denom with `PredictWrappedTokenV2`, and
requires `QuoteToken` to match that denom. `BaseAmount` must be greater than
or equal to `QuoteAmount`. The receiver gets `QuoteAmount`; the relayer gets
the fee `BaseAmount - QuoteAmount`; the proxy records the token origin for
the created voucher. Voucher creation also records the metadata image for
the wrapped denom.

**Failure ack and timeout.** Route through `refundV2`.

## ESCROW

**Verify.** Charges the rate-limit bucket, validates or burns the base
token, and increases channel balance. Native escrow requires an exact single
sent coin.

**Execute.** Validates the quote denom against V2 prediction when a metadata
image exists, otherwise falls back to V1 prediction. Mints the quote amount
to the receiver, mints the fee to the relayer, and records token origin if
the quote denom is new.

**Failure ack and timeout.** Route through `refundV2`.

## UNESCROW

**Verify.** Charges the rate-limit bucket, requires an existing token origin
for the base denom, checks that the reversed path and channel match the
origin path, and validates the wrapped denom prediction. Wrapped base denoms
are burned from the sender. Native base denoms require exact sent coins.

**Execute.** Reverses the current path, decreases channel balance, releases
`QuoteAmount` of native quote token to the receiver, and releases the fee to
the relayer.

**Failure ack and timeout.** Re-mint the IBC voucher to the sender.

## SOLVE

`TOKEN_ORDER_KIND_SOLVE` is defined for wire compatibility. Verify returns
`zkgm/v1: solve token order not implemented`, and receive returns
`zkgm/v1: solve recv not implemented`.

## Token Order Acknowledgements

Failure `Ack` tags refund through `refundV2`. Success `Ack` tags decode
`TokenOrderAck`.

`FILL_TYPE_PROTOCOL` means the receive side already settled the order, so
ack handling is a no-op.

`FILL_TYPE_MARKETMAKER` settles to the market maker. For `UNESCROW`, the
implementation re-mints the base voucher to the market maker. For
`INITIALIZE` and `ESCROW`, it releases the escrowed base amount to the
market maker through `settleEscrowedV2`.

## Predicted Denoms and Accounts

`PredictWrappedTokenV2(path, channelId, baseToken, metadataImage)`
ABI-encodes the tuple
`(uint256 path, uint32 channelId, bytes baseToken, bytes32 metadataImage)`,
hashes the encoded bytes with Keccak, takes the first 20 bytes, hex-encodes
them, and prefixes the result with `ibc/`.

`PredictWrappedTokenV1(path, channelId, baseToken)` is the legacy variant.
It uses the same derivation without the metadata image input and is
consulted only when no metadata image is recorded for the quote denom.

`MetadataImage(meta)` is `keccak256(EncodeTokenMetadata(meta))`. In V2, the
metadata image is part of the wrapped denom identity.

`PredictCallProxyAccount(path, channelId, sender)` hashes
`ZKGM_CALL_PROXY || path_bytes32 || channel_id_decimal || sender`, takes
the first 20 bytes, hex-encodes them, and prefixes the result with `zkgm1`.

## Channel Balance Accounting

Channel balances use this key shape:

```text
{channelId}/{path}/{hex(baseToken)}/{hex(quoteToken)}
```

`channelId` uses `ChannelId.String()`. `path` uses `u256.ToString()`. Token
fields are hex-encoded without a `0x` prefix.

The balance represents source-side escrow for a token order. Increases
happen when `INITIALIZE` or `ESCROW` send-side verification accepts a token
movement. Decreases happen when an `UNESCROW` receive path releases native
tokens, or when refund and market-maker settlement paths release escrowed
base tokens.

When a balance drops to zero, the implementation removes the key from
`channelBalanceV2`.
