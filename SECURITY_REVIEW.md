# gno-ibc 보안 검토 보고서

- **대상**: `onbloc/gno-ibc` (브랜치 `claude/gno-ibc-security-review-io1gS`)
- **검토 범위**: IBC v1 코어 · CometBLS / state-lens 라이트클라이언트 · UCS03 ZKGM 앱 · Union 계열 의존성(`allinbits/gno-realms` @ `852a5a0`) · gnoland stdlib(gno 핀 `72aff5a`)
- **위협 모델**: 브릿지 탈취 — 증명 위조를 통한 무담보 민팅, 에스크로 고갈, 권한/계정 탈취
- **방법론**: 신뢰 루트(라이트클라이언트 증명 검증) → 가치 회계(에스크로/민팅) → 권한 경계 → 의존성 stdlib 순으로 코드 레벨 정적 분석. 치명도 상위 발견은 콜사이트까지 직접 추적해 검증.

---

## 1. 신뢰 의존성 지도

```
gno-ibc (1st-party)
├── IBC v1 core            r/core/ibc/v1/core
├── CometBLS LC            r|p/core/ibc/lightclients/cometbls
├── state-lens LC          r/core/ibc/v1/lightclients/statelensics23mpt
│     └── p/core/ethereum/{mpt,storage} + p/core/encoding/{rlp,abi}
├── ZKGM app               r/core/ibc/v1/apps/zkgm (+ v0/impl)
│
├── Union 계열 (gno-realms @ 852a5a0)   ← "디펜던시 있는 Union protocol"
│     ├── p/aib/ics23      (ICS23 commitment proof)   ★ 신뢰 루트
│     └── p/aib/merkle, p/aib/encoding, tendermint LC
│
└── gnoland stdlib (gno @ 72aff5a)                    ← 본 보고서 추가 검토
      ├── crypto/cometblszk  (Groth16 ZK 검증기, 순수 gno)   ★ 최종 신뢰 루트
      ├── crypto/bn254       (페어링/곡선, gnark 바인딩)      ★ 페어링 건전성
      ├── crypto/keccak256, sha256, merkle, modexp
      ├── p/gnoswap/uint256  (모든 금액 산술)
      ├── p/demo/tokens/grc20 (바우처 토큰 원장)
      ├── p/nt/{avl,bptree}  (영속 원장 저장소)
      └── p/onbloc/json      (※ 브릿지에서 미사용)
```

**핵심 사실**: 브릿지의 자금 안전성은 궁극적으로 `crypto/cometblszk`(ZK 검증)와 `p/aib/ics23`(상태 증명)에 달려 있으며, 이 둘은 모두 본 검토에서 소스 레벨로 확인했습니다.

---

## 2. 발견 요약 (치명도순)

| ID | 치명도 | 위치 | 요약 | 브릿지 도달성 |
|----|--------|------|------|----------------|
| **C1** | 🔴 Critical | `v0/impl/batch.gno`,`coins.gno`,`token_order.gno` | 배치 전송이 동일 `-send` 코인을 자식마다 재검사 → 무담보 민팅/에스크로 증발 | **도달** (직접 검증) |
| **H1** | 🟠 High | `lightclients/cometbls/cometbls.gno:104` | `UpdateClient`에 높이 단조성 가드 부재 → LatestHeight 역행 | 도달 |
| **M1** | 🟡 Medium | `v0/impl/dispatch.gno:46` | `recover()`가 부분 자금 변이를 삼키고 failure ack → 이중 지급 | 도달(트리거 난이도 높음) |
| **M2** | 🟡 Medium | `gno-realms/p/aib/ics23/proof.gno:616` | `SpecEquals` 동등성 과대선언 → IAVL/TM 구조검증 우회 가능 | 도달(스펙 고정 전제 의존) |
| **M3** | 🟡 Medium | `lightclients/cometbls/cometbls.gno:142` | 증명 높이별 신뢰기간 미재확인(최신 상태만 확인) | 도달 |
| **M4** | 🟡 Medium | `p/.../cometbls/verify.gno:57` | Misbehaviour 동결 그리핑(영구 DoS) | 도달 |
| **L1** | 🟢 Low | `apps/zkgm/admin.gno` | admin 부트스트랩 무방비 + 선착순 탈취 (킬스위치 개방) | 도달 (**권한 탈취**) |
| **L2** | 🟢 Low | `apps/zkgm/proxy.gno:60`,`ledger.gno:20` | impl 권한 게이트 fail-open(리스트 비면 허용) | 운영설정상 닫힘/부트스트랩 윈도우 |
| **L3** | 🟢 Low | `gno-realms/p/aib/ics23/ops.gno:137` | `append(op.Prefix,...)` 백킹배열 에일리어싱 | 도달(메모리 안전) |
| **L4** | 🟢 Low/Info | `p/gnoswap/uint256/{conversion,arithmetic}.gno` | `Int64`/`Sub`/`SetBytes` 콜사이트 의존 함정 | 현 콜사이트 가드로 완화됨 |
| **S1** | ⚪ Info(상위DoS) | `gno/crypto/merkle/merkle.go:59` | `make([][]byte,count)` 무제한 선할당 DoS | **브릿지 미도달**(stdlib 전역) |
| **S2** | ⚪ Info | `gno/p/onbloc/json/node.gno:176` | JSON 숫자 float64 디코딩 → 대형 금액 손실 | **브릿지 미도달**(json 미사용) |
| **D1** | 🔵 설계 | `core/client.gno`,`packet.gno` | 퍼미션리스 클라이언트 등록 + 무증명 intent-recv → 불변식이 앱에 전가됨 | 도달(문서화된 의도) |

---

## 3. 상세 발견 및 수정 방향

### 🔴 C1 — 배치 전송 무담보 민팅 (Critical / 즉시 수정)

**위치**: `v0/impl/batch.gno:17-28`, `v0/impl/coins.gno:38-47`, `v0/impl/token_order.gno:27-42`

**원인**: 배치의 각 자식 토큰 오더에 **동일한 `sentCoins`를 소비 없이 반복 전달**합니다.

```go
// batch.gno — 자식마다 같은 sentCoins (차감 없음)
for i, instr := range batch.Instructions {
    if err := v.dispatchVerify(cur, channelId, sender, sentCoins, path, childSalt, instr); err != nil { ... }
}
// coins.gno — "검사"만 하고 소진하지 않음
func requireSentCoin(sent chain.Coins, denom string, amount *u256.Uint) error {
    if len(sent) != 1 || sent[0].Denom != denom || sent[0].Amount != want { return errCoinMismatch }
    return nil
}
```

`sentCoins`는 `send.gno:26`의 `rtunsafe.OriginSend()` — 실제로 프록시 에스크로에 들어온 코인입니다.

**익스플로잇**: `[ESCROW ugnot 100, ESCROW ugnot 100]` 배치를 `-send 100ugnot` 하나로 전송하면 두 자식 모두 `requireSentCoin` 통과 → `increaseChannelBalanceV2`가 100을 **두 번** 누적(200) → 상대 체인이 200 바우처 민팅. 실제 에스크로는 100. 배치 크기만큼 반복 가능, FORWARD 자식도 동일(`forward.gno:29`). 다른 사용자 담보 풀을 고갈시키는 전형적 브릿지 인플레이션. (바우처 burn 경로는 실제 잔액 차감이라 무영향 — 네이티브 escrow 한정.)

**수정 방향**:
1. (권장) 자식 처리 시 `sent`에서 실제 차감하는 누적 모델로 변경 — `verifyBatch`가 남은 코인 잔량(`remaining chain.Coins`)을 들고 다니며 각 `requireSentCoin` 성공 시 해당 denom·amount를 차감, 음수가 되면 실패. 배치 종료 후 잔량이 0이 아니면(과소 사용) 정책에 따라 허용/거부.
2. 또는 Union 레퍼런스처럼 **오더별 개별 pull**(banker로 sender→proxy 이동)을 verify 단계에서 수행하고, `OriginSend` 의존을 제거.
3. 회귀 테스트 추가: 동일 denom 다중 ESCROW 배치 + 단일 `-send` 가 **반드시 실패**해야 함 (현재 `batch_test.gno`는 `nil` 코인만 시험해 누락).

---

### 🟠 H1 — CometBLS UpdateClient 높이 역행 (High)

**위치**: `r/.../lightclients/cometbls/cometbls.gno:104`

```go
e.cs.LatestHeight = newHeight   // newHeight > LatestHeight 검사 없음
```

`VerifyHeader`는 `LatestHeight > header.TrustedHeight`만 보고 `TrustedHeight`는 공격자가 고릅니다. 신뢰기간 내 두 상태(100,200) 보유 시 150 헤더(trusted=100)를 제출하면 검증 통과 후 `LatestHeight`가 200→150으로 역행. `adapterStatus`·`GetLatestHeight`가 이를 사용하므로 핸드셰이크/타임아웃의 "최신 상태" 인식이 후퇴. **force-update 경로는 단조성 검사(`:245`)가 있는데 일반 경로만 누락** — 명백한 비대칭.

**수정 방향**: `UpdateClient`에서 새 높이 반영 전 가드 추가.
```go
if newHeight <= e.cs.LatestHeight {
    // 과거/동일 높이 헤더는 consensusState만 저장하고 LatestHeight는 advance하지 않음
} else {
    e.cs.LatestHeight = newHeight
}
```
(ibc-go 동작과 일치. 과거 높이 consensus state 저장 자체는 허용하되 LatestHeight는 단조 증가만.)

---

### 🟡 M1 — recover() 부분 변이 잔존 → 이중 지급 (Medium)

**위치**: `v0/impl/dispatch.gno:46-51` · 변이 지점 `token_order.gno:166-209`

수신 핸들러가 (수취인 release/mint → 릴레이어 수수료 release/mint)처럼 **비원자적**으로 자금을 움직이는데, 후속 단계 panic 시 `recover()`가 삼키고 failure ack를 반환합니다. 코어는 이미 receipt를 기록(`packet.gno:59`)했으므로 롤백되지 않고, 상대 체인은 failure 경로로 송신자에게 환불 → **목적지 지급 + 출발지 환불 = 이중 지급**. 현재는 후속 단계가 사실상 panic하지 않아(금액 사전검증·잔액 사전차감) 트리거가 어렵지만, recover 경계 안에 변이 단계를 추가하는 순간 활성화되는 깨지기 쉬운 패턴.

**수정 방향**: ① recover 경계 이전에 **모든 검증을 끝내고, 자금 변이는 마지막에 원자적으로** 수행(검증 단계와 실행 단계 분리). ② 또는 부분 변이 후 panic 시 명시적 보상(compensating) 처리. ③ 최소한 `recover`가 잡는 패닉을 "검증 실패"로 한정하고, 자금 변이 단계의 패닉은 재-패닉시켜 트랜잭션 전체를 abort(코어가 receipt까지 롤백)하도록 분리.

---

### 🟡 M2 — ICS23 SpecEquals 동등성 과대선언 (Medium, Union 의존성)

**위치**: `gno-realms/p/aib/ics23/proof.gno:616-654`, `ops.gno:165-218`

IAVL/Tendermint 전용 구조 검증기(`validateIavlOps`/`validateTendermintOps`)는 `spec.SpecEquals(IavlSpec())`가 true일 때만 동작합니다. 그런데 `SpecEquals`는 의도적으로 `LeafOp.Prefix`·`ChildOrder` **내용**·`EmptyChild`를 무시(주석에 "over-declares equality" 명시). 따라서 구조적으로 IAVL 형태이나 leaf prefix/child order가 다른 스펙이 이 검증기를 **건너뛸** 수 있습니다. 일반 길이 검사(`InnerOp.CheckAgainstSpec`: `!bytes.HasPrefix(op.Prefix, leafPrefix)`, min/max prefix, suffix%ChildSize)는 항상 적용되므로 "inner가 leaf를 흉내내는" 1차 방어는 유지되지만, IAVL height/version varint 검증은 누락 가능.

**안전성 전제**: **`ClientState.ProofSpecs`가 신뢰된 IAVL/TM 스펙으로 고정되고 공격자가 영향을 줄 수 없어야 함.**

**수정 방향**: ① 클라이언트 생성 시 ProofSpecs가 표준 `GetSDKProofSpecs()`로 **고정**되는지 코드로 강제(임의 스펙 주입 금지). ② 클라이언트 복구(recover) 경로는 느슨한 `SpecEquals`가 아니라 엄격한 `Equal`(`proof.gno:561`) 사용 확인. ③ 가능하면 `SpecEquals`를 구조 검증기 선택에만 쓰지 말고, 검증기를 스펙 종류와 무관하게 항상 적용하도록 상류(gno-realms)에 제안.

---

### 🟡 M3 — 증명 높이별 신뢰기간 미재확인 (Medium)

**위치**: `r/.../cometbls/cometbls.gno:142-172`

`VerifyMembership`/`VerifyNonMembership`는 `adapterStatus(e)==StatusActive`만 보는데, `adapterStatus`는 `cs.LatestHeight` 상태의 신선도만 평가합니다. 실제 증명은 임의의 오래된 `height`의 consensus state로 검증(`cs := e.consensusStates[height]`)되므로, 최신 상태만 신선하면 **만료되어야 할 과거 루트**로 멤버십을 증명할 수 있습니다(표준 IBC는 증명 높이의 consensus state도 비-만료여야 함).

**수정 방향**: 멤버십 검증 시 `e.consensusStates[height].Timestamp` 기준으로 신뢰기간(`now - ts < TrustingPeriod`)을 **그 높이에 대해** 재확인.

---

### 🟡 M4 — Misbehaviour 동결 그리핑 (Medium, 가용성)

**위치**: `p/.../cometbls/verify.gno:57-90`, 어댑터 `cometbls.gno:115-140`

`VerifyMisbehaviour`는 같은 `Height`의 byte-불일치 두 헤더가 **각각** `VerifyHeader`를 통과하면 동결합니다. 두 헤더가 **서로 다른** trusted height/validator set에서 나와도 됩니다. 리오그/포크 등으로 자연 발생한 정당한 두 헤더를 누구나 묶어 클라이언트를 **영구 동결**(deployer force-update 전까지)시킬 수 있습니다. 자금 위조는 아니나 채널 중단(griefing).

**수정 방향**: 진짜 equivocation 의미에 맞게 ① 두 헤더가 **동일 validator set**(같은 trusted state)에서 서명됐을 것을 요구하거나, ② 동일 높이에서의 충돌만을 misbehaviour로 인정하고 서로 다른 epoch 헤더 쌍은 거부. (Union/Tendermint misbehaviour 정의 정렬.)

---

### 🟢 L1 — ZKGM admin 부트스트랩 무방비 (Low, **계정/권한 탈취**)

**위치**: `apps/zkgm/admin.gno:11-17, 60-68`

loader(`v0/loader/loader.gno`)가 `SetAdmin`을 호출하지 않아 배포 직후 `adminAddressStr==""`. 이 상태에서 `mustBeAdmin()`은 **누구에게나 성공을 반환**합니다 → `Pause`/`Unpause`/`SetBucketConfig`/`SetRateLimitDisabled`(레이트리밋 킬스위치)가 무인증 개방. 또한 `SetAdmin`은 빈 상태에서 **선착순으로 admin을 탈취** 가능. 배포 트랜잭션에서 admin을 원자적으로 설정하지 않으면 프론트러닝 윈도우 존재. (전체 grep으로 first-party에 `SetAdmin` 호출 부재 확인.)

**수정 방향**: ① loader `init`에서 admin을 **원자적으로** 설정하거나, ② `init`에서 `rtunsafe.OriginCaller()`를 admin으로 캡처(코어 `client.gno`의 deployer 패턴과 동일), ③ admin 미설정 시 `mustBeAdmin`이 **모두 거부**(fail-closed)하도록 변경(부트스트랩 전엔 어떤 admin 함수도 호출 불가).

---

### 🟢 L2 — impl 권한 게이트 fail-open (Low)

**위치**: `apps/zkgm/proxy.gno:60-70, 139-144`, `ledger.gno:20-25`

`InAllowedImpls`/`requireImplCaller`/`mustBeAuthorizedImpl`는 `len(allowedImpls)==0`이면 `true`(허용). 이 게이트는 `ReleaseNative`·`SetChannelBalanceV2`·`RateLimit` 등 자금/상태 이동 진입점을 보호합니다. loader가 init에서 채우므로 운영설정에선 닫히지만, 리스트가 비는 경로나 `UpdateImpl` 최초 부트스트랩 프론트러닝 시 임의 realm이 escrow를 drain할 수 있음.

**수정 방향**: 부트스트랩 1회(최초 `UpdateImpl`)를 제외하고 빈 리스트를 **거부**(fail-closed). 부트스트랩은 deployer 한정 명시적 경로로 분리.

---

### 🟢 L3 — ICS23 append 백킹배열 에일리어싱 (Low, Union 의존성)

**위치**: `gno-realms/p/aib/ics23/ops.gno:137-141, 149-152`

```go
data := op.Prefix
data = append(data, pkey...)   // op.Prefix에 여유 cap 있으면 in-place 오염
```
`op.Prefix`에 spare capacity가 있으면 인접 버퍼(다른 proof 필드/`op.Suffix`)를 덮어쓸 수 있음. 단일 검증의 해시 출력은 정확하나, 동일 버퍼/op 재사용 시 데이터 손상 가능.

**수정 방향**: 방어적 복사 — `data := append([]byte{}, op.Prefix...)` (merkle 바인딩이 쓰는 패턴). 상류(gno-realms)에 제안.

---

### 🟢 L4 — uint256 콜사이트 함정 (Low/Info, stdlib)

`p/gnoswap/uint256`는 holiman/uint256의 충실한 포팅으로 핵심 산술(`AddOverflow`/`SubOverflow`/`MulOverflow`, 비교, `Clone`/`Set`)은 **정확**합니다. 다만 라이브러리 특성상 콜사이트 규율이 필요:
- 평문 `Sub`는 언더플로 시 **조용히 wrap**(`arithmetic.gno:30`). → 브릿지는 `decreaseChannelBalanceV2`에서 `Cmp` 선검사 후 `Sub`, 토큰버킷도 `Lt` 선검사 후 `Sub`라 **현재 가드됨**.
- `Int64()`는 바운드 체크 없음, `IsUint64()`는 63비트 경계 미보장 → 브릿지 `amountInt64`가 `IsUint64() && Uint64() > MaxInt64` 거부로 **이미 방어**.
- `SetBytes`는 32바이트 초과 입력을 조용히 절단 → 브릿지는 ABI 디코더가 고정 32바이트 워드(`abi/decode.gno:125` `SetBytes32`)만 사용해 **미도달**.

**조치**: 현재 안전. 신규 코드에서 위 3개 패턴을 깰 경우를 대비해 가이드 주석/린트 추가 권장.

---

### ⚪ S1 — crypto/merkle 무제한 선할당 DoS (상위 High, 브릿지 미도달)

**위치**: `gno/gnovm/stdlibs/crypto/merkle/merkle.go:53-72`

```go
count := int(b[0])<<24 | ... | int(b[3])   // 공격자 제어, 최대 ~2.1e9
items := make([][]byte, count)             // 길이 검증 전 선할당 → ~32GB OOM
```
가스는 입력 길이 기준(pre-call slope)이라 8바이트 입력으로 거대 할당 유발 가능 — **체인 전역 DoS**. 단, **gno-ibc는 `crypto/merkle.HashFromByteSlices`를 사용하지 않음**(grep 확인). 브릿지 경로엔 영향 없음.

**수정 방향(상류 gno)**: `make` 전에 `count <= len(b)/4` 등으로 상한. gnolang/gno에 업스트림 이슈/PR 제안 권장.

---

### ⚪ S2 — JSON 숫자 float64 디코딩 (상위 High, 브릿지 미도달)

**위치**: `gno/examples/.../p/onbloc/json/node.gno:176-180`

모든 JSON 숫자가 `float64`로 디코딩되어 `2^53` 초과 정수가 손실됩니다. 그러나 **gno-ibc는 `onbloc/json`을 import하지 않으며**, 패킷 금액은 ABI로 `*u256.Uint`(256비트 전체 정밀도)로 디코딩됩니다. 따라서 브릿지에 영향 없음.

**조치**: ① 미사용 의존성(`p/onbloc/json`)을 vendor 목록에서 제거해 공급망 표면 축소 검토. ② 향후 JSON으로 금액을 다루지 말 것(문자열+정수 파싱).

---

### 🔵 D1 — 코어 설계: 불변식의 앱 전가 (설계 권고)

코어는 (a) 클라이언트 등록을 퍼미션리스로 허용(`CreateClient` 무인증, `RegisterClient` 네임스페이스 스코프), (b) intent-recv를 무증명 fast-path로 허용합니다. 정직한 클라이언트에 묶인 정상 채널은 위조 불가하나, 코어는 앱이 **(1) 채널 하부 클라이언트 타입을 검증**하고 **(2) `OnIntentRecvPacket`이 미펀딩 fill에 revert**할 것을 강제하지 않습니다(규약). ZKGM은 이를 따름(`marketMakerFillV2`가 maker 자신의 바우처 잔액에서만 fill).

**수정 방향**: ① `assertDeployer`에 `runtime.AssertOriginCall()`을 내장해 향후 권한 진입점의 tx-origin 피싱을 구조적으로 차단. ② 위 두 불변식을 IApp 구현 필수 계약으로 문서화. ③ packet receipt/ack 센티넬 값 구분(`commit.gno`)에 회귀 방지 주석.

---

## 4. 견고하다고 확인된 부분 (Positive)

이번 검토에서 **증명 위조 1차 취약점은 발견되지 않았습니다.** 구체적으로:

- **Groth16 ZK 검증기(`crypto/cometblszk`)**: A·B·C·commitment·PoK 슬라이스, MSM, Pedersen PoK 페어링, 메인 페어링(`e(A,B)·e(C,-δ)·e(α,-β)·e(msm,-γ)=1`)이 Union Solidity 검증기를 충실히 포팅. 스칼라는 `hashToField`/SHA256-top-byte-zero로 `< r` 보장. 스텁/항상-참 경로 없음. `pairingEqualsOne`은 EIP-197 시맨틱(정확히 `0x..01`) 준수, 실패 시 fail-closed.
- **bn254 페어링 건전성(`crypto/bn254.go`)**: `parseG2`가 **`IsOnCurve()` + `IsInSubGroup()` 모두 수행**(`:134,:139`) — Groth16 건전성에 가장 중요한 G2 부분군 체크가 존재(gnark `PairingCheck`은 부분군 미검사이므로 바인딩이 보완). G1은 cofactor=1이라 on-curve로 충분. 좌표 `>= p` 거부(비정준 차단), 무한원점 명시 처리.
- **ICS23(`p/aib/ics23`)**: 존재 증명은 leaf+inner op 재계산 후 `bytes.Equal(root, subroot)`로 신뢰 루트에 고정. **비존재 증명은 좌/우 이웃 존재증명 + 엄격 부등호 순서검사**(`key`가 기존 키와 같으면 거부) — 리플레이/타임아웃 우회 방어가 건전. cosmos ics23-go 충실 포팅. 해시/길이 enum은 미지원 값에 fail-closed.
- **MPT/RLP/ABI**: 모든 노드 해시-체인 검증, no-unused-proof, 정준 인코딩 강제, RLP 길이/오버플로/trailing-byte 가드, ABI offset/length 검증 견고.
- **state-lens L1→L2 바인딩**: L2 consensus state를 L1 멤버십 증명으로 검증 후에만 storageRoot 신뢰 — 올바른 Union 설계.
- **코어 회계**: 에스크로 선행 → 패킷 커밋 순서 정확(`send.gno:74-79`), 리플레이 가드(packet receipt) 원자적 선기록(`packet.gno:59`), ack는 receipt 선행 필요, 타임아웃은 비존재 증명 필요(이중처리 방지), 핸드셰이크 OPEN은 상대 증명 필요.
- **GRC20 바우처 원장**: `math/overflow` 패닉 연산, 음수 거부, Mint는 `MaxInt64-totalSupply` 상한, Burn은 잔액 선검사, self-transfer 차단, mint/burn 권한은 `*PrivateLedger` 보유(발행 realm)로 한정 — 공개 Teller에 민팅 경로 없음.
- **AVL/B+tree**: Set 덮어쓰기/`updated` 보고 정확, 리밸런스/분할/병합에서 키 누락·중복 없음, 값 에일리어싱 위험 없음(int64 값 저장).
- **uint256**: 핵심 오버플로 산술·비교·deep copy 정확.

---

## 5. 우선순위 수정 로드맵

| 우선순위 | 항목 | 영향 | 난이도 |
|---------|------|------|--------|
| **P0** | C1 배치 escrow 이중계산 | 자금 직접 탈취 | 중 (verify 누적 모델/오더별 pull) |
| **P0** | H1 라이트클라이언트 높이 역행 | 신뢰 상태 무결성 | 소 (단조 가드 1곳) |
| **P1** | L1 admin 부트스트랩 + S 킬스위치 개방 | 권한/계정 탈취 | 소 (init 캡처 + fail-closed) |
| **P1** | M1 recover 부분변이 이중지급 | 자금(조건부) | 중 (검증/실행 분리) |
| **P1** | M2 ICS23 스펙 고정 확인 | 증명 건전성 전제 | 소~중 (스펙 고정 검증/문서화) |
| **P2** | M3 증명높이 신뢰기간 재확인 | 만료 루트 수용 | 소 |
| **P2** | M4 misbehaviour 동결 그리핑 | 가용성 | 중 |
| **P2** | L2 impl 게이트 fail-closed | 권한 | 소 |
| **P3** | L3 ICS23 append 복사 / S1 merkle 상한 | 메모리/전역DoS | 소 (상류 제안) |
| **P3** | S2 미사용 json 의존성 제거 | 공급망 표면 | 소 |
| **P3** | D1 `assertDeployer`에 AssertOriginCall 내장 + 앱 불변식 문서화 | 권한/설계 | 소 |

**공급망 메모**: 브릿지의 최종 신뢰는 `gno @ 72aff5a`(cometblszk/bn254)와 `gno-realms @ 852a5a0`(ics23) 핀에 달려 있습니다. 두 핀은 본 검토에서 소스 확인했으며, 핀 갱신 시 동일 검토(특히 cometblszk·bn254·ics23) 재수행을 권장합니다.

---

*이 보고서는 정적 코드 분석 기반이며, 동적 퍼징·정형 검증·실제 trusted-setup(VK 상수) 검증·`crypto/bn254` 네이티브 라이브러리(gnark) 자체 감사는 범위 밖입니다. P0/P1 항목은 머지 전 수정 및 회귀 테스트 추가를 권장합니다.*
