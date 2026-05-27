# Common SendRaw Procedure

This page covers the shared broadcast, verification, and handoff steps for ZKGM
`TokenOrderV2` sends.

Use the per-kind pages first to build the correct `OPERAND`:

- [TokenOrderV2 INITIALIZE](initialize.md)
- [TokenOrderV2 ESCROW](escrow.md)

## Broadcast

`SendRaw` captures `-send` coins only for direct EOA calls.

Always use:

```bash
maketx call -func SendRaw
```

Do not use `maketx run` scripts for native-token sends. In a script call, the
previous realm is the script package instead of the EOA, so `OriginSend` returns
empty and verification panics.

Template:

```bash
SALT="$(openssl rand -hex 32)"
TIMEOUT="$(python3 -c 'import time; print(int((time.time()+3600)*1_000_000_000))')"
OPERAND="<hex from the per-kind guide>"

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

Argument mapping:

```text
SendRaw(
  channelId,
  timeoutTimestamp,
  saltHex,
  version,
  opcode,
  operandHex
)
```

For any `TokenOrderV2` instruction:

```text
version = 2
opcode  = 3
```

`SendRaw(channelId, ...)` uses the Gno source channel id. Prediction helpers on
Union use the Union-side counterparty channel id paired with that Gno channel.

## Gas

Observed sends on 2026-05-20:

| Kind | Block | Gas used |
|---|---:|---:|
| `INITIALIZE` | 63 | `51552539` |
| `ESCROW` | 93 | `42649471` |

The default 50M gnokey gas limit is insufficient for `INITIALIZE`.
`-gas-wanted 200000000` covers both observed kinds with headroom.

## Verify Broadcast

A successful broadcast emits a `PacketSend` event.

Record:

- packet hash
- packet data
- source channel
- destination channel
- tx hash
- block height

Optional verification via indexer:

```bash
curl -s -X POST http://23.20.153.250:8546/graphql/query \
  -H 'Content-Type: application/json' \
  -d '{"query":"{ getTransactions(where:{success:{eq:true},response:{events:{GnoEvent:{type:{eq:\"PacketSend\"},pkg_path:{eq:\"gno.land/r/core/ibc/v1/core\"},_and:[{attrs:{key:{eq:\"packet_hash\"},value:{eq:\"0x...\"}}},{attrs:{key:{eq:\"source_channel_id\"},value:{eq:\"1\"}}},{attrs:{key:{eq:\"destination_channel_id\"},value:{eq:\"25\"}}}]}}}},order:{heightAndIndex:DESC}){ block_height hash response { events { ...on GnoEvent { type pkg_path attrs { key value } } } } } }"}'
```

Each send record should include:

- resolved inputs
- operand hex
- full gnokey command
- tx result
- verification commands

## Hand Off to Union

After a successful send, provide Union with:

- tx hash (hex and base64)
- block height
- packet hash
- packet data
- source channel id
- destination channel id
- timeout timestamp
- any placeholder values used during testing

If multiple diagnostic packets were broadcast, explicitly identify which tx hash
should be relayed.

## Operational Hazards

### `-send` Must Match BaseAmount Exactly

`requireSentCoin` rejects any mismatch between:

- sent denom
- sent amount
- operand `BaseAmount`

Off-by-one errors or extra denoms trigger:

```text
zkgm/coins: sent coin mismatch
```

### `quote_token` Must Be Correct

`INITIALIZE` packets require the exact predicted `quote_token`. `ESCROW`
packets require the wrapped token address created by the earlier `INITIALIZE`.

Empty values or placeholder addresses can still broadcast successfully but fail
during recv validation.

### Diagnostic Sends Pollute the Relayer

Every successful `SendRaw` becomes relayable.

If multiple debugging packets were broadcast, clearly identify:

- which tx hashes are obsolete
- which packet should actually be relayed

### Deployed Pkgpath Differs from Source

Source:

```text
gno.land/r/core/ibc/v1/apps/zkgm/
```

Current deployed realm:

```text
gno.land/r/gnoswap/ibc/v1/apps/zkgm
```

Always use the deployed path for `-pkgpath`.

### Salt and Timeout Must Be Fresh

Regenerate both values for every attempt:

```bash
openssl rand -hex 32
```

Timeout convention:

```text
(now + 1 hour) * 1_000_000_000
```

### Placeholder Sends Need Explicit Approval

Placeholder packets should only be broadcast after explicit approval from the
requester.

All placeholder values must be disclosed during the Union handoff.

## Appendix: Re-verification Commands

These commands are copy-paste diagnostics adapted from the 2026-05-20 send
logs. Replace the variables before running block- or packet-specific queries.

```bash
RPC_URL="http://23.20.153.250:26657"
INDEXER_URL="http://23.20.153.250:8546/graphql/query"
BLOCK_HEIGHT="<block height>"
PACKET_HASH="0x<packet hash>"
SOURCE_CHANNEL_ID="1"
DESTINATION_CHANNEL_ID="25"
```

Chain liveness:

```bash
curl -sS "$RPC_URL/status" | python3 -m json.tool
```

Indexer schema sanity:

```bash
curl -sS -X POST -H "Content-Type: application/json" \
  -d '{"query":"{ __schema { queryType { fields { name } } } }"}' \
  "$INDEXER_URL"
```

Latest indexed height:

```bash
curl -sS -X POST -H "Content-Type: application/json" \
  -d '{"query":"{ latestBlockHeight }"}' \
  "$INDEXER_URL"
```

Recent non-genesis blocks with timestamps:

```bash
curl -sS -X POST -H "Content-Type: application/json" \
  -d '{"query":"{ getBlocks(where: { height: { gt: 0 } }, order: { height: DESC }) { height time } }"}' \
  "$INDEXER_URL"
```

Confirm a transaction at the expected block height:

```bash
curl -sS -X POST -H "Content-Type: application/json" \
  -d "{\"query\":\"{ getTransactions(where: { block_height: { eq: ${BLOCK_HEIGHT} } }) { hash success block_height } }\"}" \
  "$INDEXER_URL" | python3 -m json.tool
```

Fetch full transaction details for the block, including `PacketSend` attrs and
`packet_data`:

```bash
curl -sS -X POST -H "Content-Type: application/json" \
  -d "{\"query\":\"{ getTransactions(where: { block_height: { eq: ${BLOCK_HEIGHT} } }) { hash success block_height response { events { ...on GnoEvent { type pkg_path attrs { key value } } } } } }\"}" \
  "$INDEXER_URL" | python3 -m json.tool
```

Find the specific `PacketSend` event by packet hash and channel pair:

```bash
curl -sS -X POST -H "Content-Type: application/json" \
  -d "{\"query\":\"{ getTransactions(where:{success:{eq:true},response:{events:{GnoEvent:{type:{eq:\\\"PacketSend\\\"},pkg_path:{eq:\\\"gno.land/r/core/ibc/v1/core\\\"},_and:[{attrs:{key:{eq:\\\"packet_hash\\\"},value:{eq:\\\"${PACKET_HASH}\\\"}}},{attrs:{key:{eq:\\\"source_channel_id\\\"},value:{eq:\\\"${SOURCE_CHANNEL_ID}\\\"}}},{attrs:{key:{eq:\\\"destination_channel_id\\\"},value:{eq:\\\"${DESTINATION_CHANNEL_ID}\\\"}}}]}}}},order:{heightAndIndex:DESC}){ block_height hash response { events { ...on GnoEvent { type pkg_path attrs { key value } } } } } }\"}" \
  "$INDEXER_URL" | python3 -m json.tool
```

Find recent `PacketSend` events on the Gno source channel:

```bash
curl -sS -X POST -H "Content-Type: application/json" \
  -d "{\"query\":\"{ getTransactions(where: { response: { events: { _or: [ { GnoEvent: { type: { eq: \\\"PacketSend\\\" } pkg_path: { eq: \\\"gno.land/r/core/ibc/v1/core\\\" } attrs: { key: { eq: \\\"source_channel_id\\\" } value: { eq: \\\"${SOURCE_CHANNEL_ID}\\\" } } } } ] } } } order: { heightAndIndex: DESC }) { hash block_height response { events { ...on GnoEvent { type attrs { key value } } } } } }\"}" \
  "$INDEXER_URL" | python3 -m json.tool
```
