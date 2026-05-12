# gnokey transaction query vectors — zkgm.Send

Target realm: `gno.land/r/gnoswap/ibc/v1/apps/zkgm`

This document is a runnable integration guide. Every script in the
**Happy paths** section can be copy-pasted onto a fresh `gnodev local`
boot and produces a successful `PacketSend` commit on chain.

The **Reference** section at the end records the raw output of replaying
`gno.land/p/core/ibc/zkgm/testdata/scenarios.json` (decoder-side fixtures)
through Send — every scenario hits a deterministic realm-level rejection;
the table is useful as a regression signal but does not exercise a happy
path. See the reference section for why.

## gnodev local setup

zkgm packages live on disk under `gno.land/{p,r}/core/...` but declare
module names `gno.land/{p,r}/gnoswap/...` in `gnomod.toml`. The default
`gnodev` `root=` resolver matches directory layout to import path, so the
aliased modules need explicit `local=` resolvers, plus the e2e helper
package for the channel-open shortcut used below:

```sh
gnodev local \
  -root "$HOME/.cache/gno-ibc/gno" \
  -resolver "root=$PWD" \
  -resolver "root=$HOME/.cache/gno-ibc/gno/examples" \
  -resolver "local=$PWD/gno.land/p/core/tokenbucket" \
  -resolver "local=$PWD/gno.land/p/core/ibc/zkgm" \
  -resolver "local=$PWD/gno.land/r/core/ibc/v1/apps/zkgm" \
  -resolver "local=$PWD/gno.land/r/core/ibc/v1/apps/zkgm/v0/impl" \
  -resolver "local=$PWD/gno.land/r/core/ibc/v1/apps/zkgm/v0/loader" \
  -resolver "local=$PWD/gno.land/r/core/ibc/v1/apps/zkgm/testing/e2e" \
  -paths "gno.land/r/core/ibc/v1/core,gno.land/r/core/ibc/v1/lightclients/cometbls,gno.land/r/gnoswap/ibc/v1/apps/zkgm,gno.land/r/gnoswap/ibc/v1/apps/zkgm/v0/impl,gno.land/r/gnoswap/ibc/v1/apps/zkgm/v0/loader,gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/e2e" \
  -no-web \
  -node-rpc-listener 0.0.0.0:26657
```

The loader's `init()` calls `zkgm.UpdateImpl(...)` and
`core.RegisterApp(...)` at deploy time, so the proxy and impl are wired
the moment gnodev finishes booting. No further admin step is needed.

## How to send

Every happy-path script below ends with one `zkgm.Send(...)` call. Run
them via `gnokey maketx run`:

```sh
printf '\n' | gnokey maketx run \
  -gas-fee 1000000ugnot -gas-wanted 90000000 \
  -broadcast -insecure-password-stdin \
  -chainid dev -remote tcp://127.0.0.1:26657 \
  test1 tools/zkgm-fixtures/scripts/happy/send_call.gno
```

The empty stdin (`printf '\n'`) feeds an empty password to gnokey; the
default `gnodev local` `test1` keyring has no password. Override via
`GNOKEY_PASSWORD` if your keyring is encrypted.

Each script opens its own channel pair via the in-tree helper
`gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/e2e`, which:
1. Calls `core.RegisterClient` with the `zkgm-e2e-mock` light-client type,
2. Calls `core.CreateClient` + `ConnectionOpenInit` + `ConnectionOpenAck`,
3. Calls `ChannelOpenInit` + `ChannelOpenAck` **twice** (source +
   destination) so the pair is bilaterally addressable inside one chain.

The mock light-client (`testing/e2e/mock_lc.gno`) is permissive on proofs,
so the open dance succeeds without external proof generation. **Do not
re-use this in production** — it is the smallest possible substitute that
lets `gnokey maketx run` exercise zkgm.Send end-to-end.

---

## Happy paths (verified end-to-end)

### 1. `zkgm.Send` with a single `Call`

Script: [`tools/zkgm-fixtures/scripts/happy/send_call.gno`](../../../../../tools/zkgm-fixtures/scripts/happy/send_call.gno).

What it does: open a channel pair, then build a `z.Call{Sender = signer,
Eureka = false, ContractAddress = "any-contract"}` and submit it as the
Send instruction.

```sh
printf '\n' | gnokey maketx run \
  -gas-fee 1000000ugnot -gas-wanted 90000000 \
  -broadcast -insecure-password-stdin \
  -chainid dev -remote tcp://127.0.0.1:26657 \
  test1 tools/zkgm-fixtures/scripts/happy/send_call.gno
```

Observed result (first run after gnodev boot):

```
source_channel 1
destination_channel 2
client_id 1
connection_id 1
packet.SourceChannelId 1
packet.DestinationChannelId 2
packet.TimeoutTimestamp 1700000000000000000
packet.Data.len 544
OK!
GAS WANTED: 90000000
GAS USED:   47424092
TX HASH:    <base64>
```

Emitted events (one tx):

| event | key fields |
|---|---|
| `CreateClient` | `client_type=zkgm-e2e-mock`, `client_id=1` |
| `ConnectionOpenInit` | `connection_id=1`, `client_id=1`, `counterparty_client_id=99` |
| `ConnectionOpenAck` | `connection_id=1`, `counterparty_connection_id=77` |
| `ChannelOpenInit` ×2 | `channel_id=1`, `channel_id=2`, `version=ucs03-zkgm-0` |
| `ChannelOpenAck` ×2 | `channel_id=1` (cp=2), `channel_id=2` (cp=1) |
| `PacketSend` | `packet_hash=0xfba0e1a9…`, `source_channel_id=1`, `destination_channel_id=2`, `timeout_timestamp=1700000000000000000` |

The `packet_data` attribute on `PacketSend` carries the full
ABI-encoded `ZkgmPacket` (544 bytes), with `runtime.OriginCaller().String()`
embedded as the `Call.Sender` field.

### 2. `zkgm.Send` with a `Batch` of two `Call`s

Script: [`tools/zkgm-fixtures/scripts/happy/send_batch.gno`](../../../../../tools/zkgm-fixtures/scripts/happy/send_batch.gno).

What it does: same channel-open shortcut, then `z.Batch{[Call{eureka=false},
Call{eureka=false}]}` where both inner sender fields are the tx signer.

```sh
printf '\n' | gnokey maketx run \
  -gas-fee 1000000ugnot -gas-wanted 90000000 \
  -broadcast -insecure-password-stdin \
  -chainid dev -remote tcp://127.0.0.1:26657 \
  test1 tools/zkgm-fixtures/scripts/happy/send_batch.gno
```

Observed result:

```
source_channel 3
destination_channel 4
packet.Data.len 1280
OK!
GAS USED:   51252767
```

(Source channel is 3 because the previous run already consumed 1/2 — each
`OpenE2EChannelPair` call mints fresh channel IDs.)

### 3. `zkgm.Send` with a `Forward` wrapping a `Call`

Script: [`tools/zkgm-fixtures/scripts/happy/send_forward.gno`](../../../../../tools/zkgm-fixtures/scripts/happy/send_forward.gno).

What it does: `z.Forward{Path=1, TimeoutHeight=0, TimeoutTimestamp=…,
Instruction=Call{sender=signer, eureka=false}}`. v1 accepts a single-hop
forward whose inner instruction is a Call; recursion (Forward → Forward)
is rejected.

```sh
printf '\n' | gnokey maketx run \
  -gas-fee 1000000ugnot -gas-wanted 90000000 \
  -broadcast -insecure-password-stdin \
  -chainid dev -remote tcp://127.0.0.1:26657 \
  test1 tools/zkgm-fixtures/scripts/happy/send_forward.gno
```

Observed result:

```
source_channel 5
destination_channel 6
packet.Data.len 832
OK!
```

### Why no happy path for TokenOrder

`zkgm.Send` (see `send.gno:23`) reads `banker.OriginSend()` only when
`runtime.PreviousRealm().IsUserCall()` is true. `maketx run` produces an
intermediate realm frame, so the user-call check is false and the
read returns empty — `requireSentCoin` then fails with
`zkgm/coins: sent coin mismatch` regardless of any `-send` flag on the
outer transaction.

For a TokenOrder happy path you have three options:
1. **Submit Send via `maketx call`** — requires a primitives-only wrapper
   that accepts `(channelId, timeoutTs, saltHex, version, opcode,
   operandHex)`. None exists yet; adding `SendRaw` is the natural fix.
2. **Pre-mint a voucher** (denom starting with `ibc/`) and Send with
   `Kind=ESCROW`. The `verify` path then takes the `burnVoucher` branch
   and avoids `requireSentCoin` entirely. Setup is multi-tx and lives in
   the `testing/e2e` filetests rather than `maketx run`.
3. **Drive the existing e2e filetest** at
   `gno.land/r/core/ibc/v1/apps/zkgm/testing/e2e/scenarios/z21_v1_create_client_handshake_send_filetest.gno`
   which sidesteps `zkgm.Send` and submits via `core.BatchSend` directly
   (acceptable for golden-output testing, not for replay through the
   realm's public entry).

---

## Reference: raw fixture replay (does **not** reach a successful Send)

`tools/zkgm-fixtures/scripts/gen-send-script.sh --all` renders one
`maketx run` script per entry in `scenarios.json`. Replaying these unmodified
produces deterministic realm-level panics — the fixtures carry decoder-side
test values (`Sender = "alice"`, `Eureka = true`, `BaseToken = "ibc/v1-send"`,
recursive Forward, etc.) that the Send path correctly rejects.

| # | Scenario | Observed panic | Why |
|---|---|---|---|
| 1 | `recv_call_eureka_true` | `zkgm/v1: eureka mode not supported` | fixture sets `eureka=true`; v1 stub rejects |
| 2 | `recv_call_eureka_false_empty_calldata` | `zkgm/v1: invalid call sender` | fixture `Sender="alice"` ≠ signer |
| 3 | `recv_token_order_v2_initialize_protocol_fill` | `zkgm/coins: sent coin mismatch` | INITIALIZE needs `-send` (and `maketx call`, not run) |
| 4 | `recv_token_order_v2_escrow_protocol_fill` | `zkgm/voucher: not found: ibc/v1-send` | ESCROW needs a pre-minted voucher |
| 5 | `recv_token_order_v2_unescrow_protocol_fill` | `zkgm/coins: sent coin mismatch` | UNESCROW (non-ibc denom) needs `-send` |
| 6 | `recv_token_order_v2_solve_marketmaker_fill` | `zkgm/v1: solve token order not implemented` | v1 stub |
| 7 | `recv_token_order_v1_legacy_protocol_fill` | `zkgm/v1: unsupported token order version` | dispatcher routes only V2 |
| 8 | `recv_batch_empty` | `port not found` | empty batch passes verify, then PacketSend needs an open channel |
| 9 | `recv_batch_call_then_token_order_escrow` | `zkgm/v1: eureka mode not supported` | first sub-instruction is `Call{eureka=true}` |
| 10 | `recv_forward_single_hop_call` | `zkgm/v1: eureka mode not supported` | inner Call has `eureka=true` |
| 11 | `recv_forward_recursive_two_hops_call` | `zkgm/v1: invalid forward instruction` | recursion rejected by v1 |

Reproduce the entire table on a freshly booted `gnodev local`:

```sh
for name in $(jq -r '.[].name' gno.land/p/core/ibc/zkgm/testdata/scenarios.json); do
  echo "===> $name"
  GNOKEY_REMOTE=tcp://127.0.0.1:26657 GNOKEY_CHAINID=dev GNOKEY_KEYNAME=test1 \
    tools/zkgm-fixtures/scripts/gen-send-script.sh "$name" --exec 2>&1 \
    | grep -E '^(Data: |panic: )' | head -3
  echo
done
```

A diff against the table is a behavioral regression signal: the realm's
rejection messages are stable, so any change in the line for an unchanged
scenario is worth investigating before updating this document.

## Updating this document

- **Happy paths**: re-run each of the three scripts after any change to
  `send.gno`, `impl/`, the e2e helper, or `loader.gno`. Copy fresh GAS /
  hash values into the observed-result blocks above.
- **Reference table**: re-run the loop in the previous section after any
  change to `scenarios.json` or to realm validation. A new panic line
  there is the regression signal mentioned above.
