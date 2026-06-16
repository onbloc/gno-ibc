# 컨트랙트 역할 정의 (AIB IBC 구조 기반)

AIB gno IBC(`/Users/onbloc/Workspace/gno/aib-gno-ibc`)의 책임 경계를 기준으로,
본 프로젝트의 각 계층이 **무엇을 책임지고 무엇을 위임하는지**를 명시한다. 이
문서는 리팩토링과 신규 코드의 판단 기준이다.

핵심 원칙: **계층마다 책임이 하나로 수렴해야 하고, 자기 책임이 아닌 것은
인터페이스로 위임한다.**

---

## 계층 한눈에

| 계층 | 위치 | 한 줄 책임 | 상태 |
|------|------|-----------|------|
| **pure 타입/인터페이스** | `p/onbloc/ibc/{types,host,app}` | 공유 도메인 타입·계약·순수 계산 | 없음 |
| **pure 라이브러리** | `p/onbloc/{encoding,verifier,ibc/zkgm,ibc/lightclient/*}` | 인코딩·증명검증·zkgm 와이어 | 없음 |
| **core (도메인)** | `r/onbloc/ibc/core` | IBC 프로토콜 메커니즘 + 앱 라우팅 + 상태 소유 | 소유 |
| **lightclient 어댑터** | `r/onbloc/ibc/lightclients/*` | 클라이언트 상태 + 검증 오케스트레이션 | 소유 |
| **app (도메인)** | `r/onbloc/ibc/apps/ucs03_zkgm` | 자산·도메인 비즈니스 로직 + 앱 상태 | 소유 |
| **app impl** | `r/onbloc/ibc/apps/ucs03_zkgm/v1` | 무상태 비즈니스 로직(교체 가능) | 없음 |

---

## 1. core — IBC 프로토콜 메커니즘

### DO (책임진다)
- **클라이언트/연결/채널 생명주기**: Create/Update/ForceUpdate, 4-way 핸드셰이크.
- **패킷 생명주기**: Send / Recv / Acknowledgement / Timeout, receipt·commitment 관리.
- **증명 검증 호출**: `ILightClient`에 위임. core는 *언제* 검증할지(active 가드
  포함)를 결정하고, *어떻게* 검증할지는 모른다.
- **앱 등록·라우팅**: 포트(=앱 realm pkgPath)별 `IApp` 등록, 패킷 수신 시 올바른
  앱 콜백 호출, ack 커밋.
- **상태 소유**: `State`(clients/connections/channels/commitments/receipts/ports).
  모든 영속 상태의 유일 소유자.

### DON'T (절대 안 한다)
- 토큰·denom·escrow·voucher 등 **앱 비즈니스 로직** — 0.
- **패킷 Data 해석** — `Data`는 opaque `[]byte`. 디코딩은 앱 책임.
- **증명 검증 알고리즘 구현** — 라이트클라이언트에 위임.
- 앱별 상태(ledger 등) 보유.

### 위임
- 증명 검증 → `ILightClient`
- 비즈니스 처리 → `IApp` 콜백

> 현재 상태: core는 이미 비즈니스/denom/Data해석을 하지 않는다(준수). 위반은
> **인터페이스 정의 위치**(아래 §4)와 **도메인 타입이 realm에 묶인 것**뿐.

---

## 2. app (도메인) — 비즈니스 로직만

### DO
- **자산/도메인 비즈니스**: zkgm token order의 escrow/voucher mint·burn,
  channel balance 회계, forward 추적, call 디스패치.
- **앱 상태 소유**: ledger(tokenOrigin/channelBalance/inFlight/tokenBucket),
  voucher 레지스트리.
- **IApp 콜백 구현**: `OnRecvPacket` 등은 비즈니스 처리 후 결과만 반환.
- **core 진입 호출**: 패킷 송신은 `core.PacketSend`/`BatchSend` 호출로 위임.

### DON'T
- 패킷 commitment·receipt 저장 (core의 일).
- 증명 검증 (core/라이트클라이언트의 일).
- 채널/연결 상태 관리 (콜백만 제공, 상태는 core).

### 위임
- 프로토콜(commit/proof/channel) → `core`
- 와이어 인코딩 → `p/onbloc/ibc/zkgm`

---

## 3. app impl — 무상태 비즈니스 로직 (`/v1`)

도메인(`ucs03_zkgm`)이 상태를 소유하고, `/v1`은 그 상태를 **인자로 받아**
비즈니스 규칙을 적용하는 교체 가능한 구현체다.

### 규칙 (확정)
- **자체 영속 상태 금지**: 패키지 전역 `var`/avl/params 보유 안 함.
- 도메인 데이터를 인자로 받고, 변경은 도메인의 업데이트 함수로 반영.
- 도메인이 `impl` 참조를 보유하고 게이트(`requireImplRealm`)로 보호.

---

## 4. pure 타입/인터페이스/순수계산

### `p/onbloc/ibc/types` — 공유 도메인 모델
- ID·enum: ClientId/ConnectionId/ChannelId/Height/Timestamp/Status/...
- 구조체: Packet/Channel/Connection + `EthAbiEncode`
- 메시지: 모든 `Msg*`
- 커밋먼트 계산: CommitPacket/Packets/Acks, keccak
- **상태 무의존.** core·app·lightclient가 모두 import.

### `p/onbloc/ibc/host` — IBC host 환경 계약 + 경로
- `ILightClient` / `IForceLightClient` 인터페이스 계약
- 커밋먼트 경로/키 계산(`*Path`, slot 상수)
- ICS-024류 식별자 검증

### `p/onbloc/ibc/app` — 앱 계약
- `IApp` / `IIntentApp` 인터페이스 (콜백 계약)
- core가 이 계약으로 앱을 호출, 앱이 이 계약을 구현 → 순환 의존 없음.

### 순수 라이브러리
- `encoding/{abi,rlp}`, `verifier/evm/{mpt,storage}`, `ibc/zkgm`,
  `ibc/lightclient/{cometbls,statelens}` — 알고리즘만, 상태 없음.

---

## 5. 호출 방향 (단방향 의존)

```
app(ucs03_zkgm) ──import──▶ core ──import──▶ p/onbloc/ibc/{types,host,app}
   │  ▲콜백(IApp)                  │ ▲검증(ILightClient)        ▲
   └──┘ (core가 인터페이스로 역호출) └──┘                          │
app/impl(/v1) ──▶ app(도메인 상태 게이트)                          │
lightclient 어댑터 ──▶ p/onbloc/ibc/lightclient/* ─────────────────┘
모든 realm ──▶ pure (단방향, pure는 realm을 import 안 함)
```

규칙:
1. **pure는 realm을 import하지 않는다.**
2. **core는 app을 import하지 않는다** — app이 core를 import하고 `IApp`으로 등록(의존 역전).
3. **인터페이스 계약은 pure, 구현은 realm.**
4. **도메인 타입은 `p/onbloc/ibc/types` 한 곳.** realm은 타입을 재정의하지 않는다.

---

## 6. 위반 체크리스트 (현재 → 목표)

| # | 항목 | 현재 | 목표 |
|---|------|------|------|
| V1 | IApp/ILightClient 인터페이스 위치 | core realm(`core.gno`) | pure(`app`,`host`) |
| V2 | 도메인 타입(Packet/Channel/Msg) 위치 | core realm(`types.gno` 등) | pure(`types`) |
| V3 | 커밋먼트 경로/keccak | core realm | pure(`host`/`types`) |
| V4 | core가 비즈니스 로직 | 없음 ✓ | 유지 |
| V5 | app이 콜백만(비즈니스 위임) | 대체로 ✓ | 유지·정리 |
| V6 | impl 무상태 | ✓ (proxy가 상태 소유) | 유지 |
| V7 | lightclient 순수 로직 pure화 | 완료 ✓ | 유지 |

---

## 참고
- 상세 매핑/리스크: [REFACTOR_PLAN.md](REFACTOR_PLAN.md)
- 코드 작성 규칙: [STRUCTURE_GUIDE.md](STRUCTURE_GUIDE.md)
- AIB 비교: [COMPARISON_AIB.md](COMPARISON_AIB.md)
