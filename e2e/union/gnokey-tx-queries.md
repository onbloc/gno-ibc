# gnokey registration checks

Target realm: `gno.land/r/onbloc/ibc/union/core`

The examples below activate the v1 implementations and register the IBC
app/client types used by the smoke setup. Run them in order on a freshly started
chain.

Start a local node with the IBC packages loaded:

```sh
tools/run-v1-ibc-smoke-node-gnoland.sh
```

If you added or changed a package under `gno.land/r/onbloc/ibc/union`, start
from fresh genesis so the package is deployed before the examples run:

```sh
tools/run-v1-ibc-smoke-node-gnoland.sh --reset
```

The `test1` key shipped with `gnodev local` has an empty password. Use
`-insecure-password-stdin` when running non-interactively:

```sh
echo "" | gnokey maketx run -insecure-password-stdin ... test1 /tmp/foo.gno
```

The per-section examples omit `-insecure-password-stdin` for brevity.

## 0. Grant Relayer Role

Grant the `RelayerRole` (id `1`) to addresses before running any relayer
operations. Core functions such as `UpdateClient`, `CreateClient`, and channel /
connection handshake entrypoints are gated behind this role. Without it the
transaction will be rejected with an authorization error.

The access realm's `DefaultAdminAddress`
(`g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5`) is bootstrapped with `AdminRole`
(id `0`) automatically at deploy time, but the `RelayerRole` must be granted
explicitly.

All `gnokey maketx call` invocations below must be signed by an address that
already holds `AdminRole`. On a fresh chain that is
`g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5` (the key named `test1` in the local
keystore).

** Admin relayer
```sh
gnokey maketx call \
    -pkgpath "gno.land/r/onbloc/ibc/union/access" \
    -func "GrantRole" \
    -args "1" \
    -args "g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5" \
    -gas-fee "10000000ugnot" \
    -gas-wanted "10000000" \
    -broadcast \
    -chainid "dev.ibc" \
    -remote "http://23.20.153.250:26657" \
    test1
```

** lc state-lens-ics23
```sh
gnokey maketx call \
    -pkgpath "gno.land/r/onbloc/ibc/union/access" \
    -func "GrantRole" \
    -args "1" \
    -args "g1kzk926hsc9wcqsgluckdk2vglr2ge9m3fyglpw" \
    -gas-fee "10000000ugnot" \
    -gas-wanted "10000000" \
    -broadcast \
    -chainid "dev.ibc" \
    -remote "http://23.20.153.250:26657" \
    test1
```

** lc cometbls
```sh
gnokey maketx call \
    -pkgpath "gno.land/r/onbloc/ibc/union/access" \
    -func "GrantRole" \
    -args "1" \
    -args "g1ntuwmgjxxymp232hs92wtnkcelkul9f3t388cj" \
    -gas-fee "10000000ugnot" \
    -gas-wanted "10000000" \
    -broadcast \
    -chainid "dev.ibc" \
    -remote "http://23.20.153.250:26657" \
    test1
```

Check:

```sh
cat >/tmp/check_relayer_role.gno <<'EOF'
package main

import (
	"gno.land/p/onbloc/access/manager"
	access "gno.land/r/onbloc/ibc/union/access"
)

func main(cur realm) {
	result := access.HasRole(cross(cur), manager.RoleId(1), address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5"))
	println("relayer_role_granted", result.IsMember)
}
EOF

gnokey maketx run -gas-fee 1000000ugnot -gas-wanted 2000000 -broadcast -chainid dev.ibc -remote http://23.20.153.250:26657 test1 /tmp/check_relayer_role.gno
```

Expected output includes:

```txt
relayer_role_granted true
```

## 1. UpdateImpl — core

Activates the v1 IBC host implementation.

```sh
cat >/tmp/updateimpl_core.gno <<'EOF'
package main

import core "gno.land/r/onbloc/ibc/union/core"

func main(cur realm) {
	core.UpdateImpl(cross(cur), "gno.land/r/onbloc/ibc/union/core/v1")
	println("core impl updated")
}
EOF

gnokey maketx run -gas-fee 1000000ugnot -gas-wanted 50000000 -broadcast -chainid dev.ibc -remote http://23.20.153.250:26657 test1 /tmp/updateimpl_core.gno
```

## 2. UpdateImpl — zkgm app

Activates the v1 ZKGM application implementation.

```sh
cat >/tmp/updateimpl_zkgm.gno <<'EOF'
package main

import zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"

func main(cur realm) {
	zkgm.UpdateImpl(cross(cur), "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1")
	println("zkgm impl updated")
}
EOF

gnokey maketx run -gas-fee 1000000ugnot -gas-wanted 50000000 -broadcast -chainid dev.ibc -remote http://23.20.153.250:26657 test1 /tmp/updateimpl_zkgm.gno
```

## 3. Register — ZKGM App

Registers the ZKGM proxy app with core. Core rejects re-registration so this is
safe to call once.

```sh
cat >/tmp/register_zkgm_app.gno <<'EOF'
package main

import (
	core "gno.land/r/onbloc/ibc/union/core"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
)

func main(cur realm) {
	portID := []byte(zkgm.ProxyPkgPath())
	if !core.HasApp(portID) {
		zkgm.RegisterCoreApp(cross(cur))
	}
	println("registered zkgm")
}
EOF

gnokey maketx run -gas-fee 1000000ugnot -gas-wanted 50000000 -broadcast -chainid dev.ibc -remote http://23.20.153.250:26657 test1 /tmp/register_zkgm_app.gno
```

Check:

```sh
cat >/tmp/check_zkgm_app.gno <<'EOF'
package main

import (
	core "gno.land/r/onbloc/ibc/union/core"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
)

func main() {
	portID := []byte(zkgm.ProxyPkgPath())
	println("zkgm_port", string(portID))
	println("registered", core.HasApp(portID))
}
EOF

gnokey maketx run -gas-fee 1000000ugnot -gas-wanted 50000000 -broadcast -chainid dev.ibc -remote http://23.20.153.250:26657 test1 /tmp/check_zkgm_app.gno
```

Expected output:

```txt
registered true
```

Address:

```sh
package main

import "chain"

func main() {
      println("zkgm_proxy_addr", chain.PackageAddress("gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"))
}
EOF

gnokey maketx run -gas-fee 1000000ugnot -gas-wanted 2000000 -broadcast -chainid dev.ibc -remote http://23.20.153.250:26657 test1 /tmp/check_zkgm_addr.gno
Enter password.
zkgm_proxy_addr g182p37d0cyvsvqpv49lqtphpj3jswwqtuyl4qyy

OK!
GAS WANTED: 2000000
GAS USED:   936936
HEIGHT:     12646
EVENTS:     []
INFO:       
TX HASH:    eUGyPt2Jf6wraaXvQz6W4of4Iaux7JaV7FNOL6bQ0m8=
```

## 4. Register — state-lens/ics23/mpt

Registers the state-lens/ics23/mpt light client type with core via its loader
realm. The loader realm (`gno.land/r/onbloc/ibc/union/lightclients/statelensics23mpt`)
holds the factory function in persistent state and calls `core.RegisterClient`
internally, avoiding the ephemeral-realm persistence error that would occur if
the factory were inlined in the run script.

The state-lens factory passes `core.GetLightClient` as the L1 resolver so that
the instantiated client can look up the L1 client from core at verification time.
The L1 client (tracked by `ClientState.L1ClientID`) must already exist in core
before any state-lens `VerifyMembership` / `VerifyNonMembership` call is made.

Requires the loader realm to have `RelayerRole` (see section 0).

```sh
cat >/tmp/register_statelens.gno <<'EOF'
package main

import (
	core "gno.land/r/onbloc/ibc/union/core"
	statelens "gno.land/r/onbloc/ibc/union/lightclients/statelensics23mpt"
)

func main(cur realm) {
	if !core.HasClient(statelens.ClientType) {
		statelens.RegisterClient(cross(cur))
	}
	println("registered", statelens.ClientType)
}
EOF

gnokey maketx run -gas-fee 1000000ugnot -gas-wanted 50000000 -broadcast -chainid dev.ibc -remote http://23.20.153.250:26657 test1 /tmp/register_statelens.gno
```

Check:

```sh
cat >/tmp/check_statelens.gno <<'EOF'
package main

import (
	core "gno.land/r/onbloc/ibc/union/core"
	statelens "gno.land/r/onbloc/ibc/union/lightclients/statelensics23mpt"
)

func main() {
	clientType := statelens.ClientType
	println("state_lens_client_type", statelens.ClientType)
	println("registered", core.HasClient(clientType))
}
EOF

gnokey maketx run -gas-fee 1000000ugnot -gas-wanted 50000000 -broadcast -chainid dev.ibc -remote http://23.20.153.250:26657 test1 /tmp/check_statelens.gno
```

Expected output:

```txt
registered true
```

## 5. Register — cometbls

Registers the cometbls light client type with core via its loader realm.
The loader realm (`gno.land/r/onbloc/ibc/union/lightclients/cometbls`) holds
the factory function in persistent state and calls `core.RegisterClient`
internally, avoiding the ephemeral-realm persistence error that would occur if
the factory were inlined in the run script.

`cometbls.ClientType` is `"11-cometbls"` (module-prefixed name). If you
previously registered a client using the bare string `"cometbls"`, restart the
chain before running this — client types are keyed by exact string match.

Requires the loader realm to have `RelayerRole` (see section 0).

```sh
cat >/tmp/register_cometbls.gno <<'EOF'
package main

import (
	core "gno.land/r/onbloc/ibc/union/core"
	cometbls "gno.land/r/onbloc/ibc/union/lightclients/cometbls"
)

func main(cur realm) {
	if !core.HasClient(cometbls.ClientType) {
		cometbls.RegisterClient(cross(cur))
	}
	println("registered", cometbls.ClientType)
}
EOF

gnokey maketx run -gas-fee 1000000ugnot -gas-wanted 50000000 -broadcast -chainid dev.ibc -remote http://23.20.153.250:26657 test1 /tmp/register_cometbls.gno
```

Check:

```sh
cat >/tmp/check_cometbls.gno <<'EOF'
package main

import (
	core "gno.land/r/onbloc/ibc/union/core"
	cometbls "gno.land/r/onbloc/ibc/union/lightclients/cometbls"
)

func main() {
	clientType := cometbls.ClientType
	println("cometbls_client_type", cometbls.ClientType)
	println("registered", core.HasClient(clientType))
}
EOF

gnokey maketx run -gas-fee 1000000ugnot -gas-wanted 50000000 -broadcast -chainid dev.ibc -remote http://23.20.153.250:26657 test1 /tmp/check_cometbls.gno
```

Expected output:

```txt
registered true
```

---

## Channel Info (current setup)

| Item | Value |
|---|---|
| Source chain | `dev.ibc` |
| Destination chain | `11155111` (Sepolia) |
| Source channel | `1` |
| Destination channel | `31` |
| Source port | `gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm` |
| Destination port | `0x5fbe74a283f7954f10aa04c2edf55578811aeb03` |
| Source connection | `1` (client `2`) |
| Destination connection | `40` (client `61`) |

## 6. SendRaw — TokenOrderV2 INITIALIZE (ugnot → Sepolia)

첫 번째 전송. `INITIALIZE`는 Sepolia에 wrapped ERC20을 새로 생성한다.

### 6-1. Predicted quote_token 조회

전송 전 반드시 `predictWrappedTokenV2`로 `quote_token`을 계산해야 한다.
채널이 바뀌면 반드시 재실행 — destChannel이 달라지면 predicted address도 달라진다.

**Step 1: initializer calldata 생성**

`initialize(authority, minter, name, symbol, decimals)` 인자 설명:

| 인자 | 주소 | 역할 |
|---|---|---|
| `authority` | `0x40cDFf51aE7487e0b4A4D6e5f86eB15Fb7c1d9f4` | ERC20 토큰 admin/owner |
| `minter` | `0x5FbE74A283f7954f10AA04C2eDf55578811aeb03` | ZKGM 컨트랙트 — mint/burn 권한 보유 |

```bash
cast calldata \
  "initialize(address,address,string,string,uint8)" \
  0x40cDFf51aE7487e0b4A4D6e5f86eB15Fb7c1d9f4 \
  0x5FbE74A283f7954f10AA04C2eDf55578811aeb03 \
  "gno.land" \
  "ugnot" \
  6
```

현재 결과:
```
0x8420ce9900000000000000000000000040cdff51ae7487e0b4a4d6e5f86eb15fb7c1d9f40000000000000000000000005fbe74a283f7954f10aa04c2edf55578811aeb0300000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000e000000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000008676e6f2e6c616e64000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000575676e6f74000000000000000000000000000000000000000000000000000000
```

**Step 2: predictWrappedTokenV2 호출**

`predictWrappedTokenV2(path, destChannel, baseToken, tuple(implementation, initializer))` 인자 설명:

| 인자 | 값 | 역할 |
|---|---|---|
| contract | `0x5FbE74A283f7954f10AA04C2eDf55578811aeb03` | ZKGM 컨트랙트 (Sepolia) |
| `path` | `0` | direct send (hop 없음) |
| `destChannel` | `34` | Sepolia 쪽 채널 ID |
| `baseToken` | `0x75676e6f74` | `ugnot` UTF-8 hex |
| `implementation` | `0xaf739f34ddf951cbc24fdbba4f76213688e13627` | ZkgmERC20 구현체 주소 |
| `initializer` | Step 1 결과 전체 | `initialize()` calldata (292 bytes) |

현재 채널(34) 기준 실제 명령어:

```bash
cast call 0x5FbE74A283f7954f10AA04C2eDf55578811aeb03 \
  "predictWrappedTokenV2(uint256,uint32,bytes,tuple(bytes,bytes))(address,bytes32)" \
  0 \
  34 \
  0x75676e6f74 \
  "(0xaf739f34ddf951cbc24fdbba4f76213688e13627,0x8420ce9900000000000000000000000040cdff51ae7487e0b4a4d6e5f86eb15fb7c1d9f40000000000000000000000005fbe74a283f7954f10aa04c2edf55578811aeb0300000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000e000000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000008676e6f2e6c616e64000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000575676e6f74000000000000000000000000000000000000000000000000000000)" \
  --rpc-url https://eth-sepolia.g.alchemy.com/v2/-gssAZHmR-_k76zUfYgq5
```

현재 결과:

| 항목 | 값 |
|---|---|
| ZKGM contract | `0x5FbE74A283f7954f10AA04C2eDf55578811aeb03` |
| Implementation | `0xaf739f34ddf951cbc24fdbba4f76213688e13627` |
| Authority | `0x40cDFf51aE7487e0b4A4D6e5f86eB15Fb7c1d9f4` |
| Minter | `0x5FbE74A283f7954f10AA04C2eDf55578811aeb03` |
| **quote_token** | **`0xD3fCBD2aD2DB9F204f60077F874C6159D77000Df`** |
| metadataImage (keccak) | `0xd88fadc1ab2ec844b9333691a4d85756a813cc18809fd3dbba1211ea9e3fc93f` |

- `path`: `0` (direct send)
- `destChannel`: `31` (채널 변경 시 Step 1~2 재실행 필요)
- `baseToken`: `0x75676e6f74` = `ugnot`

셀렉터 검증:

```bash
cast sig 'initialize(address,address,string,string,uint8)'
# 0x8420ce99 여야 함 (typo 주의: initializer() → 0xd0f68ee2)
```

### 6-2. Operand 인코딩

`TokenOrderV2` (kind=0, INITIALIZE) 필드:

| 필드 | 값 | 비고 |
|---|---|---|
| `Sender` | Gno 주소 | ASCII bytes `[]byte("g1...")` |
| `Receiver` | Union EOA | 20 raw bytes (0x 제거) |
| `BaseToken` | `ugnot` | ASCII bytes `0x75676e6f74` |
| `BaseAmount` | 전송량 (ugnot) | uint256, `-send`와 정확히 일치 |
| `QuoteToken` | `0xD3fCBD2aD2DB9F204f60077F874C6159D77000Df` | 20 raw bytes |
| `QuoteAmount` | 수신량 | uint256 (보통 BaseAmount와 동일) |
| `Kind` | `0` | TOKEN_ORDER_KIND_INITIALIZE |
| `Metadata` | `EncodeTokenMetadata({Implementation, Initializer})` | ABI params 인코딩 |

`TokenMetadata` (현재 값):

```text
Implementation: 0xaf739f34ddf951cbc24fdbba4f76213688e13627
Initializer:    0x8420ce9900000000000000000000000040cdff51ae7487e0b4a4d6e5f86eb15fb7c1d9f4
                  0000000000000000000000005fbe74a283f7954f10aa04c2edf55578811aeb03
                  ...  (Section 6-1 Step 1 결과값 전체)
```

> Initializer는 `cast calldata "initialize(address,address,string,string,uint8)" ...` 로 생성한 전체 hex값. 절대 truncated값 사용 금지.

인코딩 순서: `TokenMetadata` 먼저 → 그 bytes를 `TokenOrderV2.Metadata`에 넣고 → `TokenOrderV2` 전체 인코딩.
ABI flavor는 `abi_encode_params` (plain `abi.encode` 사용 금지 — 32 bytes head offset 추가됨).

### 6-3. 전송

```bash
SALT="$(openssl rand -hex 32)"
TIMEOUT="$(python3 -c 'import time; print(int((time.time()+3600)*1_000_000_000))')"
OPERAND="<위에서 인코딩한 hex>"
AMOUNT="1000000"   # ugnot, BaseAmount와 동일하게

printf '\n' | gnokey maketx call \
  -insecure-password-stdin \
  -pkgpath "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm" \
  -func "SendRaw" \
  -args "1" \
  -args "$TIMEOUT" \
  -args "$SALT" \
  -args "2" \
  -args "3" \
  -args "$OPERAND" \
  -gas-fee "5000000ugnot" \
  -gas-wanted "200000000" \
  -send "${AMOUNT}ugnot" \
  -broadcast \
  -remote "http://23.20.153.250:26657" \
  -chainid "dev.ibc" \
  test1
```

인자 매핑:

```text
SendRaw(channelId=1, timeoutTimestamp, saltHex, version=2, opcode=3, operandHex)
```

### 6-4. 확인

성공 시 `PacketSend` 이벤트 발생. 기록해둘 값:

- `packet_hash`
- `packet_data`
- block height
- source_channel_id, destination_channel_id

```bash
curl -s -X POST http://23.20.153.250:8546/graphql/query \
  -H 'Content-Type: application/json' \
  -d '{"query":"{ getTransactions(where:{success:{eq:true},response:{events:{GnoEvent:{type:{eq:\"PacketSend\"},pkg_path:{eq:\"gno.land/r/onbloc/ibc/union/core\"},_and:[{attrs:{key:{eq:\"source_channel_id\"},value:{eq:\"<source-channel-id>\"}}},{attrs:{key:{eq:\"destination_channel_id\"},value:{eq:\"<destination-channel-id>\"}}}]}}}},order:{heightAndIndex:DESC}){ block_height hash response { events { ...on GnoEvent { type pkg_path attrs { key value } } } } } }"}'
```

---

## 7. SendRaw — TokenOrderV2 ESCROW (ugnot → Sepolia)

`INITIALIZE`가 성공(acknowledged)한 이후의 후속 전송에 사용.

### 7-1. 사전 조건

- 이전 `INITIALIZE` 패킷이 Sepolia에서 acknowledged 완료
- 해당 `INITIALIZE`로 생성된 wrapped token 주소를 알고 있어야 함

### 7-2. Operand 인코딩

`TokenOrderV2` (kind=1, ESCROW) 필드:

| 필드 | 값 | 비고 |
|---|---|---|
| `Sender` | Gno 주소 | ASCII bytes `[]byte("g1...")` |
| `Receiver` | Union EOA | 20 raw bytes (0x 제거) |
| `BaseToken` | `ugnot` | ASCII bytes `0x75676e6f74` |
| `BaseAmount` | 전송량 (ugnot) | uint256, `-send`와 정확히 일치 |
| `QuoteToken` | INITIALIZE에서 생성된 wrapped token 주소 | 20 raw bytes |
| `QuoteAmount` | 수신량 | uint256 |
| `Kind` | `1` | TOKEN_ORDER_KIND_ESCROW |
| `Metadata` | empty bytes | `0x` |

`predictWrappedTokenV2` 호출 불필요. INITIALIZE의 `quote_token` 주소를 그대로 재사용.

### 7-3. 전송

```bash
SALT="$(openssl rand -hex 32)"
TIMEOUT="$(python3 -c 'import time; print(int((time.time()+3600)*1_000_000_000))')"
OPERAND="<위에서 인코딩한 hex>"
AMOUNT="1000000"   # ugnot

printf '\n' | gnokey maketx call \
  -insecure-password-stdin \
  -pkgpath "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm" \
  -func "SendRaw" \
  -args "1" \
  -args "$TIMEOUT" \
  -args "$SALT" \
  -args "2" \
  -args "3" \
  -args "$OPERAND" \
  -gas-fee "5000000ugnot" \
  -gas-wanted "200000000" \
  -send "${AMOUNT}ugnot" \
  -broadcast \
  -remote "http://23.20.153.250:26657" \
  -chainid "dev.ibc" \
  test1
```

ESCROW는 INITIALIZE보다 가스가 적게 들지만 `-gas-wanted 200000000`으로 통일 사용.

### 주의사항

- `-send` 금액 = `BaseAmount` 정확히 일치 (오차 허용 없음)
- `SALT`와 `TIMEOUT`은 매 전송마다 새로 생성
- ESCROW 전송 전 INITIALIZE ack 완료 여부 확인 필수
- 동일 salt 재사용 시 duplicate packet으로 체인에서 거절됨

### GRC20 배포
```bash
gnokey maketx call \
    -pkgpath "gno.land/r/demo/defi/grc20factory" \
    -func "New" \
    -args "footoken" \
    -args "foo" \
    -args "6" \
    -args "1000000" \
    -args "0" \
    -gas-fee "50000000ugnot" \
    -gas-wanted "50000000" \
    -broadcast \
    -chainid "dev.ibc" \
    -remote "http://23.20.153.250:26657" \
    test1
```

## GRC20 Approve (zkgm 주소 권한 부여)
- zkgm address: g182p37d0cyvsvqpv49lqtphpj3jswwqtuyl4qyy
- zkgm path: gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm

```bash
gnokey maketx call \
  -pkgpath "gno.land/r/g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5/grct" \
  -func "Approve" \
  -args "g182p37d0cyvsvqpv49lqtphpj3jswwqtuyl4qyy" \
  -args "1000000000000000" \
  -gas-fee "50000000ugnot" \
  -gas-wanted "50000000" \
  -broadcast \
  -chainid "dev.ibc" \
  -remote "http://23.20.153.250:26657" \
  test1
```

## BaseToken (Gno denom) → hex 변환

GRC20 토큰의 `BaseToken`은 native coin(`ugnot`)처럼 denom 문자열이 아니라,
`grc20reg`에 등록된 registry key 문자열 전체를 ASCII → hex 인코딩한 값이다.

registry key 형식: `<grc20factory가 배포된 pkgpath>.<symbol>`
(`grc20factory.New`가 내부적으로 `grc20reg.Register(cross, token, symbol)`를 호출하며
slug로 symbol을 사용).

이 hex 값은 `predictWrappedTokenV2`의 `baseToken` 인자와, operand의
`TokenOrderV2.BaseToken` 필드 양쪽에 동일하게 사용한다.

```bash
DENOM="gno.land/r/g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5/foo.foo"
printf '%s' "$DENOM" | xxd -p | tr -d '\n'; echo
```

현재 결과 (`gno.land/r/g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5/foo.foo` 기준):

```
0x676e6f2e6c616e642f722f67316a67386d74757475396b6868667763346e786d756863706674663070616a64686676737166352f666f6f2e666f6f
```

`xxd`가 없는 환경이면 python으로 동일하게 변환 가능:

```bash
python3 -c "import sys; print('0x' + sys.argv[1].encode().hex())" "$DENOM"
```

참고: `ugnot`은 `0x75676e6f74`.

배포된 registry key를 직접 확인하고 싶으면 (symbol이나 배포 경로가 다를 수 있으므로 가정하지 말고 검증):

```sh
cat >/tmp/check_grc20_denom.gno <<'EOF'
package main

import "gno.land/r/demo/defi/grc20reg"

func main() {
	println(grc20reg.Render(""))
}
EOF

gnokey maketx run -gas-fee 1000000ugnot -gas-wanted 2000000 -broadcast -chainid dev.ibc -remote http://23.20.153.250:26657 test1 /tmp/check_grc20_denom.gno
```

---

## 9. GRC20 토큰 전송 (Gno-native GRC20 → Sepolia, SendRaw INITIALIZE)

`ugnot`(네이티브 코인)와 달리 GRC20 토큰은 `BaseToken`, `TokenMetadata` 구성이 완전히 다르다.
아래는 `gno.land/r/g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5/foo` (`footoken`/`foo`, decimals=6) 를
채널 38로 실제 전송해서 성공한 절차.

### 9-1. 실제 배포 경로/함수 확인 (qfuncs)

이 토큰은 `grc20factory`를 거치지 않고 배포자 네임스페이스에 직접 배포된 realm이다.
`Approve`/`Transfer` 등을 호출하기 전에 실제 pkgpath와 함수 시그니처를 확인해야 한다
(가정하지 말 것 — 이전에 `grc20factory.Approve(args: "foo", spender, amount)`로 잘못 시도해서 실패했음):

```bash
gnokey query vm/qfuncs -data "gno.land/r/g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5/foo" -remote "http://23.20.153.250:26657"
```

결과: `Approve(cur realm, spender string, amount int64)`, `Transfer`, `TransferFrom`, `Mint`, `Burn`,
`BalanceOf(owner)`, `Allowance(owner, spender)`, `TotalSupply`, `Render(path)`.
`cur`는 `maketx call`에서 자동 주입되므로 `-args`에는 넣지 않는다.

### 9-2. BaseToken hex

`grc20reg`에 등록된 registry key는 **pkgpath 그대로**다. `Transfer` 이벤트의 `token` 속성에 찍히는
`<pkgpath>.<symbol>` (`...foo/foo.foo`) 은 표시용 문자열일 뿐, 실제 `BaseToken`/`predictWrappedTokenV2`
인자로 쓰는 값이 아니다 — `.foo` 붙이면 채널 예측 주소가 달라져서 recv 시 mismatch 난다.

```bash
DENOM="gno.land/r/g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5/foo"
printf '%s' "$DENOM" | xxd -p | tr -d '\n'; echo
# 0x676e6f2e6c616e642f722f67316a67386d74757475396b6868667763346e786d756863706674663070616a64686676737166352f666f6f
```

### 9-3. ⚠️ TokenMetadata — GRC20 origin은 EVM 스타일 Implementation/Initializer 금지

`ugnot`(네이티브 코인, `grc20reg`에 미등록)와 달리, `grc20reg`에 등록된 진짜 GRC20 토큰을
`TOKEN_ORDER_KIND_INITIALIZE`로 보내면 Gno 측 `Send()`가
`verifyMetadataDecimals` (`apps/ucs03_zkgm/v1/token_order.gno:669`) 를 반드시 통과해야 한다.
이 함수는 `grc20reg.Get(baseDenom)`으로 로컬 decimals를 얻고, `TokenMetadata`를
`DecodeTokenInitializerFromMetadata`로 디코딩해서 비교하는데, 이 디코더는
**`Implementation` 이 리터럴 ASCII 문자열 `"grc20"` 일 때만** 성공한다
(`p/onbloc/ibc/union/zkgm/abi.gno:305`).

EVM ZkgmERC20 주소(`0xaf739f34...`) + Solidity `initialize(...)` calldata를 넣으면
디코딩이 실패해서 `Decimals=0`으로 취급되고 로컬 decimals(6)와 안 맞아
`"token order: metadata decimals do not match the local token"` 로 즉시 revert된다.
(gas는 소모되지만 tx 자체가 실패해서 state 변경/자금 이동은 없음 — 안전하게 재시도 가능)

**GRC20-origin에서 맞는 조합:**

```
Implementation = ASCII "grc20" (5바이트, EVM 주소 아님!)
Initializer    = abi_encode_params(string name, string symbol, uint8 decimals)
                 (Solidity initialize(...) calldata 아님)
```

```bash
IMPLEMENTATION_GRC20="0x$(printf '%s' 'grc20' | xxd -p | tr -d '\n')"
# 0x6772633230

INITIALIZER_GNO=$(cast abi-encode "f(string,string,uint8)" "footoken" "foo" 6)
```

> repo의 모든 실제 시나리오 filetest(`scenario/union/send`, `receive`, `decimals` 등)가
> 예외 없이 이 `"grc20"` 태그 형식을 쓴다 — Gno-native 토큰 origin의 표준 인코딩이다.
> EVM 스타일 Implementation/Initializer는 **Sepolia에서 온 wrapped 토큰을 다시 Gno로 보낼 때**처럼
> origin이 EVM ERC20인 경우에만 해당하는 것으로 보임 (별도 확인 필요).
>
> 반대로 Sepolia 실컨트랙트의 `predictWrappedTokenV2`는 `"grc20"` 태그를 넣어도 revert 없이
> 결정론적 주소를 반환한다(내부적으로 bytes를 그대로 해시에 사용하는 것으로 추정). 다만 실제
> relayer가 recv를 처리할 때 Sepolia 쪽이 이 태그를 진짜로 해석해서 wrapped ERC20을 초기화하는지는
> **아직 미검증** — 실패하면 Gno가 source chain이므로 timeout 경유 환불 경로를 타게 됨.

### 9-4. predictWrappedTokenV2 (grc20 태그)

```bash
cast call 0x5FbE74A283f7954f10AA04C2eDf55578811aeb03 \
  "predictWrappedTokenV2(uint256,uint32,bytes,tuple(bytes,bytes))(address,bytes32)" \
  0 \
  38 \
  0x676e6f2e6c616e642f722f67316a67386d74757475396b6868667763346e786d756863706674663070616a64686676737166352f666f6f \
  "($IMPLEMENTATION_GRC20,$INITIALIZER_GNO)" \
  --rpc-url https://eth-sepolia.g.alchemy.com/v2/-gssAZHmR-_k76zUfYgq5
```

실제 결과 (채널 38, footoken/foo/decimals=6 기준):

| 항목 | 값 |
|---|---|
| quote_token | `0x4D11bA07F13B30ef2Ec5Cd427a1e469c1F3e9967` |
| metadataImage | `0x04dd38b39b906dde21ad09a0989e898b10f2f8c570b4df23b90fffae6520492d` |

### 9-5. Operand 인코딩 (kind=0 INITIALIZE)

```bash
SENDER_ASCII="0x$(printf '%s' 'g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5' | xxd -p | tr -d '\n')"
RECEIVER="0x40cDFf51aE7487e0b4A4D6e5f86eB15Fb7c1d9f4"
BASE_TOKEN="0x676e6f2e6c616e642f722f67316a67386d74757475396b6868667763346e786d756863706674663070616a64686676737166352f666f6f"
QUOTE_TOKEN="0x4D11bA07F13B30ef2Ec5Cd427a1e469c1F3e9967"

METADATA=$(cast abi-encode "f(bytes,bytes)" "$IMPLEMENTATION_GRC20" "$INITIALIZER_GNO")

OPERAND=$(cast abi-encode "f(bytes,bytes,bytes,uint256,bytes,uint256,uint8,bytes)" \
  "$SENDER_ASCII" "$RECEIVER" "$BASE_TOKEN" 1000000 "$QUOTE_TOKEN" 1000000 0 "$METADATA")
```

### 9-6. SendRaw

Approve(9절 위 참조)로 zkgm proxy에 allowance를 준 뒤 실행. GRC20이라 `-send`는 붙이지 않는다:

```bash
SALT="$(openssl rand -hex 32)"
TIMEOUT="$(python3 -c 'import time; print(int((time.time()+3600)*1_000_000_000))')"

printf '\n' | gnokey maketx call \
  -insecure-password-stdin \
  -pkgpath "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm" \
  -func "SendRaw" \
  -args "1" \
  -args "$TIMEOUT" \
  -args "$SALT" \
  -args "2" \
  -args "3" \
  -args "$OPERAND" \
  -gas-fee "5000000ugnot" \
  -gas-wanted "200000000" \
  -broadcast \
  -remote "http://23.20.153.250:26657" \
  -chainid "dev.ibc" \
  test1
```

### 9-7. 실제 성공 기록 (참고용)

- TX HASH: `5l95XwIxYDUH4BqTTmcWYVaBB9354hqX7ZKr0uKwOxg=`
- packet_hash: `0xa8454b5b287bd4e4da465d483d04209c9873f65f8f5336872b9d8abe5379530f`
- source_channel_id=1 (connection 1, client 2) → destination_channel_id=38 (connection 48, client 75)
- `Transfer` 이벤트: `foo` 1,000,000 이 `g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5` → zkgm proxy(`g182p37d0cyvsvqpv49lqtphpj3jswwqtuyl4qyy`)로 escrow
- 이후 Sepolia 쪽 recv 결과(성공/실패)는 아직 확인 전 — indexer로 ack 상태 추적 필요

---

## 10. GRC20 배포 — standalone (팩토리 아님, `addpkg`)

> **네이밍 변경**: 기존 `footoken`/`foo`(pkgpath `.../foo`)는 `grc20reg.Register` 누락 버그로
> 재배포가 필요해서, 이름을 `grctoken`/`grct`로 바꾸고 pkgpath도 `.../grct`로 새로 잡았다.
> (한번 `GRCToken`/`GRCT`로 대문자 섞어 갔다가, 그냥 전부 소문자로 통일.) Section 6~9에 나오는
> `footoken`/`foo`/`.../foo` 기록은 그 당시 실제로 실행했던 내용이라 과거 기록으로 그대로 두고,
> 아래부터는 새 이름 기준으로 배포한다. gno pkgpath 세그먼트는 소문자만 허용되므로 애초에
> symbol도 소문자로 가는 게 맞다.

`gno.land/r/g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5/grct`는 `grc20factory.New`(위 "GRC20
배포" 섹션, `symbol` 인자 필요)가 아니라, `foo20.gno` 패턴을 따르는 **standalone realm**이다.
한 realm = 토큰 하나, 함수에 `symbol` 파라미터가 없다
(`Approve(cur realm, spender address, amount int64)` — 인자 2개뿐, `cur`는 자동 주입).

파일: `~/Downloads/grctoken/grctoken.gno`, `~/Downloads/grctoken/gnomod.toml`
(package명 `grctoken`, name=`grctoken`, symbol=`grct` — 전부 소문자)

### 10-1. `gnomod.toml`

```toml
module = "gno.land/r/g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5/grct"

gno = "0.9"
```

### 10-2. `grctoken.gno`

`grc20.NewToken(0, cur, name, symbol, decimals)`로 토큰 하나를 생성하고, `init(cur realm)`에서
배포자(`addpkg` 서명자, `cur.Previous().Address()`)에게 초기 발행량 전체를 민팅한다.
name=`grctoken`, symbol=`grct`, decimals=`6`, 초기 발행량 `1,000,000,000 * 10^6`.

**`init()` 안에서 `grc20reg.Register(cross(cur), Token, "")`를 반드시 같이 호출해야 한다** —
10-6 참고. 이걸 빠뜨리면 배포는 성공하지만 zkgm `SendRaw`가 `grc20reg.Get(baseDenom)`에서
토큰을 못 찾아 실패한다.

전체 소스: `~/Downloads/grctoken/grctoken.gno` 참고.

### 10-3. 배포 (addpkg)

```bash
gnokey maketx addpkg \
  -pkgpath "gno.land/r/g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5/grct" \
  -pkgdir "$HOME/Downloads/grctoken" \
  -gas-fee "50000000ugnot" \
  -gas-wanted "50000000" \
  -broadcast \
  -chainid "dev.ibc" \
  -remote "http://23.20.153.250:26657" \
  test1
```

`gnomod.toml`이 없으면 `gnomod.toml not found for package "..."` panic으로 실패한다 — `-pkgdir`
폴더에 `.gno` 파일과 `gnomod.toml`이 같이 있어야 함. pkgpath는 대문자를 쓰면 즉시
`expected user package path for "MPUserAll" but got "..."` panic이 난다 — 세그먼트는
소문자(`a-z0-9`, 하이픈/언더스코어)만 허용됨.

### 10-4. 배포 확인

```bash
# Render: 이름/심볼/decimals/총발행량 한번에
gnokey query vm/qrender \
  -data "gno.land/r/g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5/grct:" \
  -remote "http://23.20.153.250:26657"

# 배포자(=owner) 잔액
gnokey query vm/qeval \
  -data 'gno.land/r/g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5/grct.BalanceOf("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")' \
  -remote "http://23.20.153.250:26657"

# decimals만
gnokey query vm/qeval \
  -data "gno.land/r/g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5/grct.Token.GetDecimals()" \
  -remote "http://23.20.153.250:26657"
```

### 10-5. 트러블슈팅 — `signature verification failed`

`addpkg`/`call` 브로드캐스트 시 다음 에러가 나면 서명 자체가 잘못된 게 아니라, 서명 시점에
조회한 `sequence`와 실제 tx 처리 시점의 온체인 `sequence`가 달라서 발생한다
(`tm2/pkg/sdk/auth/ante.go:255-269` — sign bytes에 chain-id/account_number/sequence가
포함되어 재구성·검증되기 때문에, 어긋나면 "서명 검증 실패"로만 보인다. 별도의 "invalid
sequence" 에러가 아님):

```txt
Data: std.UnauthorizedError{...}
signature verification failed; verify correct account, sequence, and chain-id
```

원인은 대부분 같은 키(`g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5`)로 relayer/스모크테스트
스크립트 등 다른 프로세스가 동시에 tx를 쏘는 race — gnokey가 sequence를 조회한 직후 다른 tx가
먼저 그 sequence를 소비해버리는 경우.

체크리스트:
```bash
# chain-id 확인
curl -s http://23.20.153.250:26657/status | python3 -m json.tool | grep -A1 network

# 계정 상태(account_number/sequence/잔액) 확인
gnokey query auth/accounts/g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5 -remote "http://23.20.153.250:26657"
```
둘 다 정상이면 그냥 재시도(매번 최신 sequence를 새로 조회하므로 보통 바로 해결됨). 반복되면
같은 키를 쓰는 relayer/스크립트를 잠깐 멈추거나 배포용 키를 따로 쓴다.

### 10-6. ⚠️ `grc20reg.Register`는 토큰 자기 자신이 self-call로만 등록 가능

`grc20reg.Register(cur realm, token *grc20.Token, slug string)`는 registry key를
`cur.Previous().PkgPath()`(= `Register`를 호출한 realm의 pkgpath)로 만든다
(`examples/gno.land/r/demo/defi/grc20reg/grc20reg.gno:23-29`). 즉:

- `grct` 패키지의 `init()` (또는 다른 함수) **안에서** `grc20reg.Register(cross(cur), Token, "")`를
  호출해야만 `grct`의 pkgpath로 등록된다.
- 외부에서 (다른 realm이나 `maketx run` 스크립트에서) 대신 등록해줄 방법이 없다 —
  그렇게 하면 registry key가 호출자 쪽 pkgpath로 등록돼서 완전히 다른 항목이 생긴다.

처음(리셋 전) 배포했던 `footoken`/`foo` 소스에는 이 호출이 있었는데, 재배포하면서 새로 쓴
소스에서 빠뜨렸던 게 원인이었다. `vm/qfuncs`로 노출 함수 목록을 확인해도 `Register`가 별도로
없고, `init()`에서 호출 안 됐으면 등록이 안 된 상태로 배포가 끝난다 — 이 경우 zkgm `SendRaw`가
`grc20reg.Get(baseDenom)`에서 토큰을 못 찾아 `TOKEN_ORDER` 전송이 실패한다. 그래서 이름을
`grctoken`/`grct`로 바꿔 새 pkgpath(`.../grct`)로 재배포한다 (10절 상단 참고).

**고쳤으면 반드시 재배포해야 한다** — `init()`은 배포(`addpkg`) 시점에 딱 한 번만 실행되고
이미 배포된 realm은 수정 불가(immutable)이므로:

1. 체인을 다시 리셋하거나, 같은 `pkgpath`를 못 쓰면 새 경로로 배포 (여기서는 `.../grct`로 변경)
2. 고친 `grctoken.gno`(`grc20reg.Register(cross(cur), Token, "")` 포함, 10-2 참고)로 `addpkg` 실행 (10-3)
3. 등록 확인:
   ```bash
   cat >/tmp/check_grc20_denom.gno <<'EOF'
   package main

   import "gno.land/r/demo/defi/grc20reg"

   func main() {
   	println(grc20reg.Render(""))
   }
   EOF

   gnokey maketx run -gas-fee 1000000ugnot -gas-wanted 2000000 -broadcast -chainid dev.ibc -remote http://23.20.153.250:26657 test1 /tmp/check_grc20_denom.gno
   ```
   출력에 `gno.land/r/g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5/grct`가 나와야 정상.
