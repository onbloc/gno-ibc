# gnokey transaction query vectors — ZKGM

Target realm: `gno.land/r/gnoswap/ibc/v1/apps/zkgm`

The copy-paste transactions below exercise ZKGM on a single local node with a
mock light client and locally opened channel pairs. They are intended as smoke
checks for `gnokey`, not as production relayer examples.

## Local Smoke Node

Start a local node with core, cometbls, ZKGM, and the ZKGM helper package
loaded:

```sh
tools/run-v1-ibc-smoke-node.sh
```

The script defaults to:

```sh
GNO_ROOT=$HOME/.cache/gno-ibc/gno
GNO_IBC_ROOT=<repo root>
RPC_LISTENER=0.0.0.0:26657
```

The ZKGM loader runs at package load time and calls `core.RegisterApp`, so
there is no separate `maketx` step for app registration. The script includes
extra `local` resolvers because ZKGM module paths use
`gno.land/{p,r}/gnoswap/...`, while source directories live under
`gno.land/{p,r}/core/...` in this repository.

All examples use the default `gnodev local` `test1` key, whose password is
empty. The leading `printf '\n'` feeds that empty password to `gnokey`.

## 1. Send Call

Source: `tools/zkgm-fixtures/scripts/happy/send_call.gno`.

Copy-paste transaction:

```sh
printf '\n' | gnokey maketx run \
  -gas-fee 1000000ugnot -gas-wanted 90000000 \
  -broadcast -insecure-password-stdin \
  -chainid dev -remote tcp://127.0.0.1:26657 \
  test1 tools/zkgm-fixtures/scripts/happy/send_call.gno
```

Verify:

```txt
packet.Data.len 544
OK!
```

The emitted events must include `PacketSend`.

## 2. Send Batch

Source: `tools/zkgm-fixtures/scripts/happy/send_batch.gno`.

Copy-paste transaction:

```sh
printf '\n' | gnokey maketx run \
  -gas-fee 1000000ugnot -gas-wanted 90000000 \
  -broadcast -insecure-password-stdin \
  -chainid dev -remote tcp://127.0.0.1:26657 \
  test1 tools/zkgm-fixtures/scripts/happy/send_batch.gno
```

Verify:

```txt
packet.Data.len 1280
OK!
```

The emitted events must include `PacketSend`.

## 3. Send Forward

Source: `tools/zkgm-fixtures/scripts/happy/send_forward.gno`.

Copy-paste transaction:

```sh
printf '\n' | gnokey maketx run \
  -gas-fee 1000000ugnot -gas-wanted 90000000 \
  -broadcast -insecure-password-stdin \
  -chainid dev -remote tcp://127.0.0.1:26657 \
  test1 tools/zkgm-fixtures/scripts/happy/send_forward.gno
```

Verify:

```txt
packet.Data.len 832
OK!
```

The emitted events must include `PacketSend`.

## 4. SendRaw TokenOrder Initialize

`zkgm.SendRaw` is the `maketx call` wrapper for TokenOrder sends that need
banker coins. `maketx run` cannot make `banker.OriginSend()` visible to
`zkgm.Send`, but direct `maketx call` with `-send` can.

First generate a fresh channel pair and the raw instruction arguments:

```sh
printf '\n' | gnokey maketx run \
  -gas-fee 1000000ugnot -gas-wanted 90000000 \
  -broadcast -insecure-password-stdin \
  -chainid dev -remote tcp://127.0.0.1:26657 \
  test1 tools/zkgm-fixtures/scripts/happy/sendraw_token_order_args.gno
```

Copy the printed values into the variables below, then submit:

```sh
SOURCE_CHANNEL=<source_channel>
TIMEOUT_TIMESTAMP=<timeout_timestamp>
SALT_HEX=<salt_hex>
VERSION=<version>
OPCODE=<opcode>
OPERAND_HEX=<operand_hex>

printf '\n' | gnokey maketx call \
  -gas-fee 1000000ugnot -gas-wanted 90000000 \
  -broadcast -insecure-password-stdin \
  -chainid dev -remote tcp://127.0.0.1:26657 \
  -pkgpath gno.land/r/gnoswap/ibc/v1/apps/zkgm \
  -func SendRaw \
  -args "$SOURCE_CHANNEL" \
  -args "$TIMEOUT_TIMESTAMP" \
  -args "$SALT_HEX" \
  -args "$VERSION" \
  -args "$OPCODE" \
  -args "$OPERAND_HEX" \
  -send 100ugnot \
  test1
```

Verify:

```txt
OK!
```

The emitted events must include `PacketSend`.

## 5. Recv TokenOrder Escrow

Source: `tools/zkgm-fixtures/scripts/happy/recv_token_order.gno`.

Copy-paste transaction:

```sh
printf '\n' | gnokey maketx run \
  -gas-fee 1000000ugnot -gas-wanted 90000000 \
  -broadcast -insecure-password-stdin \
  -chainid dev -remote tcp://127.0.0.1:26657 \
  test1 tools/zkgm-fixtures/scripts/happy/recv_token_order.gno
```

Verify:

```txt
voucher_denom ibc/<predicted>
voucher_balance 21
OK!
```

The emitted events must include `PacketRecv`, `WriteAck`, and a GRC20
`Transfer` mint to the receiver.

## 6. Recv Call Failure Ack

Source: `tools/zkgm-fixtures/scripts/happy/recv_call.gno`.

Copy-paste transaction:

```sh
printf '\n' | gnokey maketx run \
  -gas-fee 1000000ugnot -gas-wanted 90000000 \
  -broadcast -insecure-password-stdin \
  -chainid dev -remote tcp://127.0.0.1:26657 \
  test1 tools/zkgm-fixtures/scripts/happy/recv_call.gno
```

Verify:

```txt
packet.Data.len 576
OK!
```

The emitted events must include `PacketRecv` and `WriteAck`. This probe
intentionally targets an unregistered receiver, so the acknowledgement is a
failure ack while the transaction still succeeds.

## 7. Recv Batch TokenOrders

Source: `tools/zkgm-fixtures/scripts/happy/recv_batch.gno`.

Copy-paste transaction:

```sh
printf '\n' | gnokey maketx run \
  -gas-fee 1000000ugnot -gas-wanted 90000000 \
  -broadcast -insecure-password-stdin \
  -chainid dev -remote tcp://127.0.0.1:26657 \
  test1 tools/zkgm-fixtures/scripts/happy/recv_batch.gno
```

Verify:

```txt
alpha_denom ibc/<predicted-alpha>
alpha_balance 11
beta_denom ibc/<predicted-beta>
beta_balance 22
OK!
```

The emitted events must include `PacketRecv`, `WriteAck`, and GRC20 `Transfer`
mints for both voucher denoms.
