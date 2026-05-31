# gno-ibc 보안 감사 보고서

- 대상: `onbloc/gno-ibc` (브랜치 `claude/gno-ibc-security-review-io1gS`)
- 의존성 핀: gno 툴체인 `72aff5a` (`.gno-version`), `allinbits/gno-realms` `852a5a0`, `gnoswap` `d720706`
- 작성일: 2026-05-31

---

## 1. 감사 스코프와 중점 사항

자금이 걸린 브릿지이므로 "증명 위조 → 무담보 민팅 / 에스크로 고갈", "리플레이/이중지급", "권한·계정 탈취"를 위협 모델로 두고, 신뢰 루트에서 가치 회계, 권한 경계 순으로 코드 정적 분석했다. 치명도 상위 항목은 콜사이트까지 추적해 익스플로잇 가능성을 직접 검증했다.

| 레이어 | 대상 | 중점 | 비교 레퍼런스 |
|---|---|---|---|
| ZK 검증기 | `crypto/cometblszk` (순수 gno) | Groth16 페어링·MSM·PoK, 스칼라 범위, 스텁 부재 | Union `CometblsZKVerifier.sol`/`CometblsClient.sol` |
| 페어링 곡선 | `crypto/bn254` (gnark 바인딩) | 좌표 범위·on-curve·**G2 부분군** 체크 | EIP-196/197, gnark-crypto v0.14 |
| 상태 증명 | `p/aib/ics23` (Union 계열) | 존재/비존재 증명, 스펙 강제, 순서검사 | cosmos `ics23-go`, ibc-go |
| L1↔L2 | `statelensics23mpt`, `p/core/ethereum/{mpt,storage}`, `encoding/{rlp,abi}` | MPT 해시체인, storageRoot 바인딩, 디코더 경계 | go-ethereum trie, Ethereum RLP/ABI |
| IBC 코어 | `r/core/ibc/v1/core` | 클라이언트/포트 등록 권한, packet receipt/ack/timeout 권한·증명 게이팅 | ibc-go ICS-04, ADR pr22/pr83/pr87 |
| ZKGM 앱 | `apps/zkgm` + `v0/impl` | 에스크로/민팅 가치보존, 리플레이, 포워딩·배치, 레이트리밋, admin | Union UCS03 ZKGM |
| 산술/저장 | `uint256`, `grc20`, `avl`/`bptree` | 오버플로, int64 narrowing, 원장 무결성 | holiman/uint256 |

치명도 기준: **Critical** 직접적 자금 손실 · **High** 무결성/대규모 영향 또는 영구 잠김 · **Medium** 조건부 자금 영향/가용성 · **Low** 방어심화/운영 의존.

---

## 2. 발견 요약

| ID | 치명도 | 위치 | 요약 | 브릿지 도달성 |
|----|--------|------|------|---------------|
| **C1** | Critical | `v0/impl/batch.gno:23`, `coins.gno:43`, `token_order.gno:37,41` | 배치 자식이 동일 `-send` 코인을 소비 없이 재검사 → 무담보 민팅 | 도달 (검증완료) |
| **H1** | High | `lightclients/cometbls/cometbls.gno:104` | `UpdateClient` 높이 단조성 가드 부재 → LatestHeight 역행 | 도달 |
| **H2** | High | `lightclients/cometbls/cometbls.gno:209-260` | `ForceUpdateClient`가 만료/동결 미검사 → deployer가 라이브 클라이언트 임의 교체 = 에스크로 전체 탈취 | 도달 (중앙화) |
| **T1** | High | `apps/zkgm/send.gno:79`, `core/packet.gno:203` | 최소/비영(非零) 타임아웃 미강제 → 미수신 패킷 영구 잠김 | 도달 |
| **M1** | Medium | `v0/impl/dispatch.gno:46-51` | `recover()`가 부분 자금 변이를 삼키고 failure ack → 이중지급 | 도달(트리거 난이도 높음) |
| **M2** | Medium | `gno-realms p/aib/ics23/proof.gno:616` | `SpecEquals` 동등성 과대선언 → IAVL/TM 구조검증 우회 | 도달(스펙 고정 전제) |
| **M3** | Medium | `lightclients/cometbls/cometbls.gno:142-172,285` | 증명 높이별 신뢰기간 미재확인(최신 상태만 확인) | 도달 |
| **M4** | Medium | `p/.../cometbls/verify.gno:57-90` | Misbehaviour 동결 그리핑(영구 DoS) | 도달 |
| **L1** | Low | `apps/zkgm/admin.gno:11-17,60-68` | admin 부트스트랩 무방비 + 선착순 탈취(킬스위치 개방) | 도달 (권한) |
| **L2** | Low | `apps/zkgm/proxy.gno:60-70,139-144`, `ledger.gno:20-25` | impl 권한 게이트 fail-open(리스트 비면 허용) | 부트스트랩 윈도우 |
| **L3** | Low | `gno-realms p/aib/ics23/ops.gno:137-152` | `append(op.Prefix,...)` 백킹배열 에일리어싱 | 도달(메모리 안전) |
| **L4** | Low/Info | `uint256/conversion.gno:11-35`, `arithmetic.gno:30` | `Int64`/`Sub`/`SetBytes` 콜사이트 함정 | 현 콜사이트 가드로 완화 |
| **D1** | 설계 | `core/client.gno:20`, `core/packet.gno:115` | 퍼미션리스 클라이언트 등록 + 무증명 intent-recv → 불변식이 앱에 전가 | 도달(문서화된 의도) |
| **S1** | Info(상위 High) | `gno crypto/merkle/merkle.go:59` | `make([][]byte,count)` 무제한 선할당 DoS | **브릿지 미도달** |
| **S2** | Info(상위 High) | `gno p/onbloc/json/node.gno:176` | JSON 숫자 float64 → 대형 금액 손실 | **브릿지 미도달**(json 미사용) |

---

## 3. 발견 상세 (원인 / 영향 / 수정 / 테스트)

### C1 · Critical · 배치 전송 무담보 민팅

**위치**: `v0/impl/batch.gno:17-28`, `v0/impl/coins.gno:38-47`, `v0/impl/token_order.gno:27-42`, 입력원 `send.gno:26`

**원인**: 배치 verify가 각 자식 토큰오더에 동일 `sentCoins`를 **차감 없이** 전달한다.
```go
// batch.gno:23 — 자식마다 같은 sentCoins
if err := v.dispatchVerify(cur, channelId, sender, sentCoins, path, childSalt, instr); err != nil { ... }
// coins.gno:43 — 검사만, 소진 안 함
if len(sent) != 1 || sent[0].Denom != denom || sent[0].Amount != want { return errCoinMismatch }
```
`sentCoins`는 `OriginSend()`(`send.gno:26`)로 실제 에스크로에 들어온 코인이다. `requireSentCoin` 성공 후 `increaseChannelBalanceV2`(`token_order.gno:41`)가 자식마다 누적된다.

**영향**: `[ESCROW ugnot 100, ESCROW ugnot 100]`를 `-send 100ugnot` 하나로 전송 → 채널 잔액 200 기록(실에스크로 100) → 상대 체인 200 바우처 민팅. 배치 크기만큼 반복, FORWARD 자식도 동일(`forward.gno:29`). 담보 풀 희석 = 기존 예치자 자금 손실. (바우처 burn 경로는 실잔액 차감이라 무영향 — 네이티브 escrow 한정.)

**수정**:
- (권장) `verifyBatch`가 남은 코인 잔량 `remaining chain.Coins`를 들고 다니며 자식 성공 시 해당 denom·amount를 **차감**, 부족하면 실패. 종료 후 잔량 정책 결정.
- 또는 Union 레퍼런스처럼 자식별 banker pull(sender→proxy)로 전환하고 `OriginSend` 의존 제거.

**테스트** (`v0/impl/batch_test.gno` 신규):
- 동일 denom 다중 ESCROW + 단일 `-send` → **실패해야 함**(현재 통과 = 버그).
- 다중 오더 총합 = `-send` 정확히 일치 시에만 성공, 초과/부족 시 실패.
- FORWARD+ESCROW 혼합 배치의 코인 이중 사용 거부.

### H1 · High · 라이트클라이언트 높이 역행

**위치**: `lightclients/cometbls/cometbls.gno:104`

**원인**: `e.cs.LatestHeight = newHeight`를 무조건 대입한다. `VerifyHeader`는 `LatestHeight > header.TrustedHeight`만 보고 `TrustedHeight`는 공격자가 고른다(`verify.gno:20`). force-update 경로는 단조성 가드(`:245`)가 있으나 일반 경로만 누락.

**영향**: 신뢰기간 내 두 상태 보유 시 더 낮은 높이 헤더로 `LatestHeight` 역행. `adapterStatus`·`GetLatestHeight`가 이를 사용해 핸드셰이크/타임아웃의 "최신 상태" 인식이 후퇴.

**수정**: 반영 전 가드 추가 — `newHeight > e.cs.LatestHeight`일 때만 advance. 과거 높이 consensus state 저장 자체는 허용하되 LatestHeight는 단조 증가만(ibc-go 동작).

**테스트**(`cometbls_test.gno`): 100·200 저장 후 150(trusted=100) 헤더 적용 → consensusStates[150]은 생기되 `LatestHeight == 200` 유지.

### H2 · High · ForceUpdateClient 만료/동결 미검사 (중앙화 핵심)

**위치**: `lightclients/cometbls/cometbls.gno:209-260` (`applyForceUpdate`)

**원인**: ChainID/TrustingPeriod/ContractAddress 보존과 높이 단조 증가만 강제하고, **클라이언트가 만료/동결인지 확인하지 않는다**. "복구용"은 주석(`:226,:251`)일 뿐 강제되지 않음.

**영향**: deployer가 **정상 라이브 클라이언트의 consensus state(root)를 임의 값으로 교체** → 위조 멤버십 증명으로 가짜 UNESCROW 수신 → 에스크로 전체 방출. `AssertOriginCall`(`client.gno:80`)은 피싱만 차단. deployer 단일 키 = 전체 자금 권한.

**수정**:
- `applyForceUpdate`에 상태 가드 추가 — `adapterStatus(e)`가 `StatusExpired` 또는 `StatusFrozen`일 때만 허용.
- 운영: deployer를 멀티시그+타임락으로, 안정화 후 거버넌스 이관. §5 참조.

**테스트**(`cometbls_test.gno`): Active 클라이언트에 force-update → 거부. Expired/Frozen → 허용 후 FrozenHeight=0.

### T1 · High · 최소 타임아웃 미강제 → 영구 잠김

**위치**: `apps/zkgm/send.gno:12,79`, `core/packet.gno:203`, 포워드 상속 `forward.gno:119`

**원인**: `Send`가 호출자의 `timeoutTimestamp`를 검증 없이 전달하고 `timeoutHeight`는 항상 0(`send.gno:79`). `PacketTimeout`은 `TimeoutTimestamp == 0`이면 거부(`packet.gno:203`)하고 **height 기반 타임아웃 경로가 없다**.

**영향**: `timeoutTimestamp == 0`(또는 상대가 도달 못 할 먼 미래값)으로 보낸 미수신 패킷은 타임아웃 불가 → 출발지 에스크로 영구 잠김. 포워드 자식은 `forward.TimeoutTimestamp` 상속이라 0이면 더 위험.

**수정**: `Send`/`sendPacket`에서 `timeoutTimestamp != 0 && timeoutTimestamp > now + minWindow` 강제(또는 height 타임아웃 경로 구현). 포워드 빌드 시에도 동일 검증.

**테스트**(`apps/zkgm/.../send_test.gno`, `rate_limit_test.gno` 인접): `Send(timeoutTimestamp=0)` → panic. 과거값 → 거부. 미래값 → 미수신 시 `PacketTimeout` 성공·환불.

### M1 · Medium · recover() 부분 변이 → 이중지급

**위치**: `v0/impl/dispatch.gno:46-51`, 변이 지점 `token_order.gno:166-209`

**원인**: 수신 핸들러가 (수취인 release/mint → 릴레이어 수수료) 비원자적으로 자금을 움직이는데, 후속 단계 panic 시 `recover()`가 삼키고 failure ack 반환. 코어는 이미 receipt 기록(`packet.gno:59`)이라 롤백 안 됨 → 상대가 송신자 환불 → 목적지 지급 + 출발지 환불.

**영향**: 현재는 후속 단계 패닉이 사실상 없어(금액 사전검증·잔액 사전차감) 트리거 어려움. recover 경계 안에 변이 단계 추가 시 활성화되는 깨지기 쉬운 패턴.

**수정**: 검증 단계와 자금 변이 단계 분리 — recover 경계 이전 모든 검증 완료, 자금 변이는 마지막에 원자적으로. 변이 단계 패닉은 재-패닉시켜 트랜잭션 전체 abort(코어 receipt까지 롤백).

**테스트**: 수수료 mint 단계 강제 패닉 주입 → receipt 미잔존(tx revert) 확인, failure-ack 미발생.

### M2 · Medium · ICS23 SpecEquals 동등성 과대선언 (Union 의존성)

**위치**: `gno-realms p/aib/ics23/proof.gno:616-654`, `ops.gno:165-218`

**원인**: IAVL/TM 전용 구조검증기는 `SpecEquals(IavlSpec())` true일 때만 동작하는데, `SpecEquals`가 `LeafOp.Prefix`·`ChildOrder` 내용·`EmptyChild`를 의도적으로 무시. 구조적으로 IAVL 형태이나 prefix/order가 다른 스펙이 검증기를 건너뛸 수 있음. 일반 길이검사(`ops.gno:220-243`)는 항상 적용되어 1차 방어는 유지.

**영향**: IAVL height/version varint 검증 누락 가능. 안전성이 `ClientState.ProofSpecs` 고정 전제에 의존.

**수정**: 클라이언트 생성 시 ProofSpecs를 표준 스펙으로 **고정**(임의 주입 금지) 검증. 복구 경로는 엄격 `Equal`(`proof.gno:561`) 사용 확인. 가능하면 상류(gno-realms)에 검증기 무조건 적용 제안.

**테스트**: 비표준(prefix 변형) IAVL-유사 스펙 주입 시 거부 확인.

### M3 · Medium · 증명 높이별 신뢰기간 미재확인

**위치**: `lightclients/cometbls/cometbls.gno:142-172`, `:285`

**원인**: `VerifyMembership`/`VerifyNonMembership`가 `adapterStatus`(=`LatestHeight` 상태 신선도)만 보고, 실제 증명은 임의 과거 `height`의 consensus state로 검증(`:152,:168`).

**영향**: 최신 상태만 신선하면 만료되어야 할 과거 루트로 멤버십 증명 통과 가능.

**수정**: 멤버십 검증 시 `e.consensusStates[height].Timestamp` 기준 `now - ts < TrustingPeriod`를 그 높이에 대해 재확인.

**테스트**: 신뢰기간 초과한 과거 높이 증명 → 거부.

### M4 · Medium · Misbehaviour 동결 그리핑

**위치**: `p/.../cometbls/verify.gno:57-90`, 어댑터 `cometbls.gno:125-137`

**원인**: 같은 `Height`의 byte-불일치 두 헤더가 각각 `VerifyHeader` 통과하면 동결. 두 헤더가 서로 다른 trusted height/validator set이어도 됨(`cometbls.gno:125-132`).

**영향**: 리오그/포크 등 자연 발생 두 헤더로 누구나 클라이언트 영구 동결(deployer 복구 전까지). 해당 채널 in-flight 자금 잠김.

**수정**: 두 헤더가 동일 validator set(같은 trusted state)에서 서명됐을 것을 요구하거나, 동일 높이 충돌만 인정.

**테스트**: 서로 다른 trusted height의 정당한 두 헤더 → misbehaviour 거부.

### L1 · Low · admin 부트스트랩 무방비 (권한 탈취)

**위치**: `apps/zkgm/admin.gno:11-17,60-68`

**원인**: loader가 `SetAdmin`을 호출하지 않아 배포 직후 `adminAddressStr == ""`. 이때 `mustBeAdmin()`이 모두 통과(`:61`) → `Pause`/`SetRateLimitDisabled`/`SetBucketConfig` 무인증 개방. `SetAdmin`은 빈 상태에서 선착순 탈취 가능(`:13`).

**영향**: 배포~admin설정 사이 프론트러닝 윈도우. 공격자가 admin 탈취 후 킬스위치 무력화/Pause.

**수정**: loader `init`에서 admin 원자적 설정(또는 `init`에서 `OriginCaller` 캡처), admin 미설정 시 `mustBeAdmin` **전면 거부**(fail-closed).

**테스트**: admin 미설정 상태에서 `Pause`/`SetRateLimitDisabled` → panic. `SetAdmin` 1회 후 타 주소 호출 → 거부.

### L2 · Low · impl 권한 게이트 fail-open

**위치**: `apps/zkgm/proxy.gno:60-70,139-144`, `ledger.gno:20-25`

**원인**: `InAllowedImpls`/`requireImplCaller`/`mustBeAuthorizedImpl`가 `len(allowedImpls)==0`이면 `true`. `ReleaseNative`·`SetChannelBalanceV2`·`RateLimit` 보호. loader가 채우므로 운영설정은 닫힘.

**영향**: 리스트가 비는 경로/`UpdateImpl` 최초 부트스트랩 프론트러닝 시 임의 realm이 escrow drain.

**수정**: 부트스트랩 1회(deployer 한정 명시 경로)를 제외하고 빈 리스트 거부(fail-closed).

**테스트**: 빈 allowedImpls에서 `ReleaseNative` 외부 realm 호출 → 거부.

### L3 · Low · ICS23 append 백킹배열 에일리어싱 (Union 의존성)

**위치**: `gno-realms p/aib/ics23/ops.gno:137-141,149-152`

**원인**: `data := op.Prefix; data = append(data, pkey...)` — `op.Prefix`에 여유 cap 있으면 인접 버퍼 in-place 오염.

**영향**: 단일 검증 해시 출력은 정확하나 동일 버퍼/op 재사용 시 데이터 손상 가능.

**수정**: 방어적 복사 `data := append([]byte{}, op.Prefix...)`. 상류 제안.

### L4 · Low/Info · uint256 콜사이트 함정 (현재 가드됨)

**위치**: `uint256/conversion.gno:11-35`, `arithmetic.gno:30`

핵심 산술(`AddOverflow`/`SubOverflow`/`MulOverflow`, 비교, `Clone`/`Set`)은 정확. 단 라이브러리 특성상:
- 평문 `Sub`는 언더플로 시 조용히 wrap → 브릿지는 `decreaseChannelBalanceV2`(`channel_balance.gno:35`)에서 `Cmp` 선검사 후 사용 → **가드됨**.
- `Int64`/`IsUint64`는 63비트 경계 미보장 → 브릿지 `amountInt64`(`voucher.gno:90`)가 `> MaxInt64` 거부 → **가드됨**.
- `SetBytes`는 32바이트 초과 시 절단 → ABI 디코더가 고정 `SetBytes32`(`abi/decode.gno:125`)만 사용 → **미도달**.

**조치**: 현재 안전. 신규 코드에서 위 패턴 위반 방지용 가이드 주석/린트 권장.

### D1 · 설계 · 불변식의 앱 전가

**위치**: `core/client.gno:20`, `core/packet.gno:115-145`

코어는 클라이언트 등록을 퍼미션리스(`CreateClient` 무인증, `RegisterClient` 네임스페이스 스코프)로, intent-recv를 무증명 fast-path로 허용한다. 정직한 클라이언트에 묶인 정상 채널은 위조 불가하나, 코어는 (1) 앱이 채널 하부 클라이언트 타입 검증, (2) `OnIntentRecvPacket`이 미펀딩 fill에 revert할 것을 강제하지 않는다(규약). ZKGM은 준수(`marketMakerFillV2`가 maker 자신 잔액에서만 fill).

**수정**: `assertDeployer`에 `runtime.AssertOriginCall()` 내장(향후 권한 진입점 tx-origin 피싱 구조적 차단). 위 두 불변식을 IApp 구현 필수 계약으로 문서화.

### S1 · Info(상위 High) · crypto/merkle 무제한 선할당 DoS — 브릿지 미도달

**위치**: `gno gnovm/stdlibs/crypto/merkle/merkle.go:53-72`

`count`(4바이트, 공격자 제어)로 `make([][]byte, count)`를 길이검증 전 선할당 → 8바이트 입력으로 ~32GB OOM(체인 전역). **gno-ibc는 `crypto/merkle.HashFromByteSlices` 미사용**(grep 확인)이라 브릿지 경로 무영향.

**수정(상류 gno)**: `make` 전 `count <= len(b)/4` 상한. gnolang/gno 업스트림 제안 권장.

### S2 · Info(상위 High) · JSON 숫자 float64 — 브릿지 미도달

**위치**: `gno examples/.../p/onbloc/json/node.gno:176-180`

모든 JSON 숫자가 float64로 디코딩되어 2^53 초과 정수 손실. **gno-ibc는 `onbloc/json` 미import**, 패킷 금액은 ABI로 `*u256.Uint`(256비트) 디코딩이라 무영향.

**조치**: 미사용 의존성(`p/onbloc/json`) vendor 목록 제거로 공급망 표면 축소 검토. 향후 JSON으로 금액 처리 금지.

---

## 4. 라이브니스 / 릴레이어 재개성 (확인 결과)

질문: "한 릴레이어가 멈추면 다른 릴레이어가 이어받을 수 있는가? 자금이 멈추거나 사라지는가?"

**확인: 릴레이는 완전 퍼미션리스이며 재개 가능하다. 정상적 IBC 가정(정직한 릴레이어 ≥1 + 살아있는 상대 체인) 하에서 자금은 멈추지 않는다.** 근거:

- `PacketRecv`/`IntentPacketRecv`/`PacketAcknowledgement`/`PacketTimeout` 모두 `relayer := OriginCaller()`만 읽고 화이트리스트 없음(`packet.gno:81,116,148,190`).
- 멱등성: 중복 recv는 receipt 존재 시 skip(`packet.gno:50`), ack/timeout은 commitment 없으면 skip(`:168,192`). → 릴레이어 교체 후 재제출 안전.
- 포워딩(async) 해소: 자식 ack→부모 ack 전파(`impl.gno:51`), 자식 timeout→부모 실패 ack(`universalErrorAck`) 기록→상류 환불(`impl.gno:65`). in-flight는 두 경우 모두 소비.
- 필러 자금은 릴레이어 비종속: 정산 대상은 ack에 기록된 marketMaker 주소(`token_order.gno:280-285`).
- Pause 중 recv 거부는 자금 안전: `OnRecvPacket` panic(`app.gno:50`)→tx revert→상대에서 (타임아웃 설정 시) 타임아웃·환불.

**예외(반드시 인지)**: C1(희석 손실), **T1(타임아웃 0/도달불가 → 영구 잠김)**, 상대 체인 영구정지/클라이언트 동결(M4) → 유일 탈출구가 deployer `ForceUpdateClient`(H2 중앙화와 직결).

---

## 5. 비상 통제 / 중앙화 위험

**평가: 중앙화 위험 HIGH.** "직접 출금" 함수는 없으나 실질적으로 전체 자금을 통제하는 단일-키 권한이 2개 있고, **타임락·멀티시그·거버넌스는 코드 전역에서 0건**(grep 확인).

| 권한 주체 | 함수 | 자금 영향 | 게이트 | 위험 |
|---|---|---|---|---|
| core deployer (단일 주소) | `ForceUpdateClient` (H2) | 에스크로 100% 탈취 가능 | `assertDeployer`+`AssertOriginCall` | god-mode |
| allowedImpls realm | `UpdateImpl` (`proxy.gno:45`) | impl 핫스왑 → 임의 drain | `InAllowedImpls` | god-mode |
| zkgm admin (미설정 시 누구나, L1) | `Pause`/`Unpause` | 송수신 차단(DoS) | `mustBeAdmin` | 검열/DoS |
| zkgm admin | `SetRateLimitDisabled`/`SetBucketConfig` | 유일한 유출 throttle 무력화 | `mustBeAdmin` | 중 |
| impl realm | `ReleaseNative` | 에스크로 직접 전송 | `requireImplCaller` | 정상(impl 신뢰 전제) |
| core deployer | `RegisterClientForType`/`RegisterAppForPort` | 클라이언트/포트 바인딩 | `assertDeployer` | 중 |

**완화 권장**:
1. deployer 및 impl-업그레이드 권한을 **멀티시그+타임락**으로(현재 단일 주소 즉시 실행).
2. **`ForceUpdateClient`를 만료/동결 한정**(H2). 안정화 후 비활성화/거버넌스 이관.
3. `ForceUpdateClient`·`UpdateImpl`·`Pause` 이벤트 온체인 모니터링/알림.
4. admin 원자적 설정 + 미설정 fail-closed(L1), impl 게이트 fail-closed(L2).

---

## 6. 견고하다고 확인된 부분

증명 위조 1차 취약점은 발견되지 않았다.

- **Groth16 ZK 검증기(`crypto/cometblszk`)**: 페어링/MSM/PoK 흐름이 Union Solidity 검증기를 충실히 포팅. 스칼라는 `hashToField`/SHA256-top-byte-zero로 `< r` 보장. 스텁/항상-참 경로 없음. `pairingEqualsOne`은 EIP-197(정확히 `0x..01`) 준수, 실패 시 fail-closed.
- **bn254(`bn254.go`)**: `parseG2`가 on-curve + **G2 부분군(`IsInSubGroup`)** 모두 검증(`:134,:139`) — gnark `PairingCheck`이 부분군 미검사이므로 바인딩이 보완. G1은 cofactor=1이라 on-curve로 충분. 좌표 `>= p` 거부.
- **ICS23(`p/aib/ics23`)**: 존재 증명은 op 재계산 후 `bytes.Equal(root, subroot)`로 신뢰 루트 고정. 비존재 증명은 좌/우 이웃 존재증명 + 엄격 순서검사(같은 키 거부) → 리플레이/타임아웃 우회 방어 건전. 해시/길이 enum 미지원 값 fail-closed.
- **MPT/RLP/ABI**: 노드 해시체인 검증, no-unused-proof, 정준 인코딩 강제, RLP 길이/오버플로/trailing-byte 가드, ABI offset/length 검증 견고. state-lens L1→L2 storageRoot 바인딩 정확.
- **코어 회계**: 에스크로 선행→커밋 순서(`send.gno:74-79`), receipt 원자적 리플레이 가드(`packet.gno:59`), ack=receipt 선행, timeout=비존재증명 요구, 핸드셰이크 OPEN=상대증명 요구.
- **GRC20 바우처 원장**: `math/overflow` 패닉 연산, 음수 거부, Mint는 `MaxInt64-totalSupply` 상한, Burn 잔액 선검사, self-transfer 차단, mint/burn 권한은 `*PrivateLedger`(발행 realm) 한정.
- **AVL/B+tree**: Set 덮어쓰기/`updated` 정확, 리밸런스에서 키 누락·중복 없음.

---

## 7. 우선순위 로드맵

| 우선순위 | 항목 | 영향 | 난이도 |
|---|---|---|---|
| **P0** | C1 배치 escrow 이중계산 | 자금 직접 손실 | 중 |
| **P0** | H1 높이 역행 | 무결성 | 소 |
| **P0** | H2 ForceUpdateClient 만료-한정 + 키 운영 | 자금 전체(중앙화) | 소(코드)+운영 |
| **P1** | T1 최소 타임아웃 강제 | 영구 잠김 | 소 |
| **P1** | L1 admin 부트스트랩 fail-closed | 권한 탈취 | 소 |
| **P1** | M1 recover 부분변이 이중지급 | 자금(조건부) | 중 |
| **P1** | M2 ICS23 스펙 고정 검증 | 증명 건전성 전제 | 소~중 |
| **P2** | M3 증명높이 신뢰기간 재확인 | 만료 루트 수용 | 소 |
| **P2** | M4 misbehaviour 동결 그리핑 | 가용성 | 중 |
| **P2** | L2 impl 게이트 fail-closed | 권한 | 소 |
| **P3** | L3 ICS23 복사 / S1 merkle 상한(상류) | 메모리/전역 DoS | 소 |
| **P3** | S2 미사용 json 의존성 제거 / D1 문서화·AssertOriginCall 내장 | 공급망/설계 | 소 |

**공급망 메모**: 최종 신뢰는 gno `72aff5a`(cometblszk/bn254)와 gno-realms `852a5a0`(ics23) 핀에 의존. 핀 갱신 시 cometblszk·bn254·ics23 재검토 권장.

**범위 밖**: 동적 퍼징, 정형 검증, trusted-setup(VK 상수) 검증, gnark 네이티브 라이브러리 자체 감사는 포함하지 않음.
