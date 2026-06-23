# IBC Union UCS03-ZKGM Proxy Realm

Upgradeable proxy realm for the IBC Union UCS03-ZKGM application.

The proxy keeps the stable app identity, package path, persistent store, access
gates, receiver registry, voucher ledger capabilities, and admin surfaces. The
installed implementation realm supplies the swappable protocol logic behind the
`IApp` interface.

## Files

- [app.gno](app.gno) exposes the core-facing IBC Union app and intent app
  callbacks.
- [types.gno](types.gno) defines the proxy/implementation/store interfaces.
- [store.gno](store.gno) owns persistent ZKGM state and guards injected store
  writes with the current crossing realm token.
- [upgrade.gno](upgrade.gno) registers and installs implementation realms.
- [register.gno](register.gno) registers the proxy app and OP_CALL receivers.
- [admin.gno](admin.gno), [access.gno](access.gno), and
  [assert.gno](assert.gno) define admin selectors and gates.
- [transfer.gno](transfer.gno) exposes the user-facing `Send` wrapper.
- [voucher.gno](voucher.gno) owns wrapped GRC20 voucher handles and ledger
  capability access.
- [getters.gno](getters.gno) exposes read-only ZKGM query helpers.
- [events.gno](events.gno) emits ZKGM proxy events.
- [gnokey_tx_queries_zkgm.md](gnokey_tx_queries_zkgm.md) records operational
  query examples.

## Implementation

- [v1/](v1/) is the canonical implementation realm registered by this proxy.

## IBC Union Spec Surface Index

The tables below use Union ZKGM `ExecuteMsg`, nested `IbcUnionMsg`,
`RestrictedExecuteMsg`, and `QueryMsg` variants as the row source. `-` means this
proxy does not expose a matching Gno public surface. `N/A (...)` marks a Union
surface that is intentionally not applicable to the Gno runtime or local state
model.

For the cross-module comparison guide, see
[docs/ibc-union-spec-comparison.md](../../../../../../../docs/ibc-union-spec-comparison.md).

### Execute

| Gno surface | IBC Union surface | Reference | Notes |
| --- | --- | --- | --- |
| [App callbacks](app.gno) | `ExecuteMsg::IbcUnionMsg` | [msg.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/msg.rs#L91), [contract.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/contract.rs#L132) | Wrapper for core-driven app callbacks below. |
| N/A (CosmWasm runtime) | `ExecuteMsg::InternalExecutePacket` | [msg.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/msg.rs#L94), [contract.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/contract.rs#L215) | CosmWasm internal runtime self-call used to resume packet execution; Gno does not import this runtime boundary. |
| N/A (CosmWasm runtime) | `ExecuteMsg::InternalWriteAck` | [msg.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/msg.rs#L103), [contract.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/contract.rs#L237) | CosmWasm internal runtime self-call used to write deferred acknowledgements; Gno does not import this runtime boundary. |
| N/A (CosmWasm runtime) | `ExecuteMsg::InternalBatch` | [msg.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/msg.rs#L106), [contract.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/contract.rs#L208) | CosmWasm internal runtime self-call used for batch execution; Gno does not import this runtime boundary. |
| [Send](transfer.gno) | `SendMsg::Send` | [msg.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/msg.rs#L125), [contract.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/contract.rs#L258) | Gno direct Send wrapper delegates to the installed implementation. |

### IBC Union App Callbacks

| Gno surface | IBC Union surface | Reference | Notes |
| --- | --- | --- | --- |
| [OnChannelOpenInit](app.gno) | `IbcUnionMsg::OnChannelOpenInit` | [msg.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/msg.rs#L91), [module.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/core/msg/src/module.rs#L9), [contract.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/contract.rs#L132) | Core-facing channel open init callback. |
| [OnChannelOpenTry](app.gno) | `IbcUnionMsg::OnChannelOpenTry` | [msg.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/msg.rs#L91), [module.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/core/msg/src/module.rs#L16), [contract.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/contract.rs#L141) | Core-facing channel open try callback. |
| [OnChannelOpenAck](app.gno) | `IbcUnionMsg::OnChannelOpenAck` | [msg.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/msg.rs#L91), [module.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/core/msg/src/module.rs#L24), [contract.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/contract.rs#L151) | Core-facing channel open ack callback. |
| [OnChannelOpenConfirm](app.gno) | `IbcUnionMsg::OnChannelOpenConfirm` | [msg.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/msg.rs#L91), [module.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/core/msg/src/module.rs#L31), [contract.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/contract.rs#L156) | Core-facing channel open confirm callback. |
| [OnChannelCloseInit](app.gno) | `IbcUnionMsg::OnChannelCloseInit` | [msg.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/msg.rs#L91), [module.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/core/msg/src/module.rs#L36), [contract.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/contract.rs#L188) | Core-facing channel close init callback. |
| [OnChannelCloseConfirm](app.gno) | `IbcUnionMsg::OnChannelCloseConfirm` | [msg.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/msg.rs#L91), [module.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/core/msg/src/module.rs#L41), [contract.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/contract.rs#L196) | Core-facing channel close confirm callback. |
| [OnIntentRecvPacket](app.gno) | `IbcUnionMsg::OnIntentRecvPacket` | [msg.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/msg.rs#L91), [module.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/core/msg/src/module.rs#L46), [contract.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/contract.rs#L167) | Delegates intent packet execution. |
| [OnRecvPacket](app.gno) | `IbcUnionMsg::OnRecvPacket` | [msg.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/msg.rs#L91), [module.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/core/msg/src/module.rs#L52), [contract.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/contract.rs#L162) | Delegates packet execution. |
| [OnAcknowledgementPacket](app.gno) | `IbcUnionMsg::OnAcknowledgementPacket` | [msg.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/msg.rs#L91), [module.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/core/msg/src/module.rs#L58), [contract.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/contract.rs#L172) | Delegates acknowledgement handling. |
| [OnTimeoutPacket](app.gno) | `IbcUnionMsg::OnTimeoutPacket` | [msg.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/msg.rs#L91), [module.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/core/msg/src/module.rs#L64), [contract.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/contract.rs#L177) | Delegates timeout handling. |

### Query

| Gno surface | IBC Union surface | Reference | Notes |
| --- | --- | --- | --- |
| [PredictWrappedToken](../../../../../../p/onbloc/ibc/union/zkgm/predict.gno) | `QueryMsg::PredictWrappedToken` | [msg.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/msg.rs#L203), [contract.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/contract.rs#L3125) | Gno exposes the derivation as a pure package helper, not a proxy query. |
| [PredictWrappedTokenV2](../../../../../../p/onbloc/ibc/union/zkgm/predict.gno) | `QueryMsg::PredictWrappedTokenV2` | [msg.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/msg.rs#L211), [contract.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/contract.rs#L3144) | Gno exposes the derivation as a pure package helper, not a proxy query. |
| N/A (no minter contract) | `QueryMsg::GetMinter` | [msg.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/msg.rs#L220), [contract.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/contract.rs#L3163) | Gno manages voucher handles and ledger capability in proxy state; there is no separate token minter contract to query. |
| [GetTokenBucket](getters.gno) | `QueryMsg::GetTokenBucket` | [msg.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/msg.rs#L221), [contract.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/contract.rs#L3167) | Reads the configured rate-limit bucket through the proxy getter and returns a snapshot. |
| N/A (v1 balance unsupported) | `QueryMsg::GetChannelBalance` | [msg.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/msg.rs#L224), [contract.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/contract.rs#L3171) | Union v1 channel-balance query; Gno ZKGM does not support the v1 balance surface. |
| [GetChannelBalanceV2](getters.gno) | `QueryMsg::GetChannelBalanceV2` | [msg.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/msg.rs#L229), [contract.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/contract.rs#L3182) | Reads the v2 escrow balance through the proxy getter and returns a cloned amount. |
| N/A (split config model) | `QueryMsg::GetConfig` | [msg.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/msg.rs#L235), [contract.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/contract.rs#L3201) | Union config is split across the Gno access realm, local rate-limit state, and non-applicable CosmWasm code-id/minter fields. |
| - | `QueryMsg::GetBurnAddress` | [msg.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/msg.rs#L236), [contract.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/contract.rs#L3205) | Union burn-address sentinel branch is not implemented, and there is no matching Gno query surface. |

### Admin

| Gno surface | IBC Union surface | Reference | Notes |
| --- | --- | --- | --- |
| [access realm](../../access/README.md) / [access.gno](access.gno) | `ExecuteMsg::AccessManaged` | [msg.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/msg.rs#L112), [contract.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/contract.rs#L276) | Replaced by the Gno access realm plus ZKGM selector gates. |
| [access realm](../../access/README.md) / [access.gno](access.gno) | `ExecuteMsg::Restricted` | [msg.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/msg.rs#L114), [contract.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/contract.rs#L279) | Replaced by the Gno access realm plus per-admin selector gates. |
| N/A (v1 balance unsupported) | `RestrictedExecuteMsg::MigrateV1ToV2` | [msg.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/msg.rs#L143), [contract.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/contract.rs#L318) | Union v1-to-v2 storage migration; Gno ZKGM does not support the v1 balance surface, so there is no matching migration surface. |
| [SetBucketConfig](admin.gno) | `RestrictedExecuteMsg::SetBucketConfig` | [msg.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/msg.rs#L148), [contract.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/contract.rs#L288) | Admin rate-limit bucket configuration. |
| N/A (no minter contract) | `RestrictedExecuteMsg::MigrateMinter` | [msg.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/msg.rs#L155), [contract.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/contract.rs#L322) | CosmWasm token-minter migration surface; Gno has no separate token minter contract, so there is no corresponding public surface. |
| [SetRateLimitDisabled](admin.gno) | `RestrictedExecuteMsg::SetRateLimitDisabled` | [msg.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/msg.rs#L162), [contract.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/contract.rs#L331) | Admin rate-limit enablement switch. |
| N/A (CosmWasm code id) | `RestrictedExecuteMsg::UpdateDummyCodeId` | [msg.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/msg.rs#L166), [contract.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/contract.rs#L340) | CosmWasm code-id setting; no Gno public surface. |
| N/A (CosmWasm code id) | `RestrictedExecuteMsg::UpdateCwAccountCodeId` | [msg.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/msg.rs#L169), [contract.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/contract.rs#L347) | CosmWasm code-id setting; no Gno public surface. |
| [Pausable](admin.gno) | `RestrictedExecuteMsg::Pausable` | [msg.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/msg.rs#L173), [contract.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/contract.rs#L357) | Admin pause/unpause wrapper. |
| [UpdateImpl](upgrade.gno) | `RestrictedExecuteMsg::Upgradable` | [msg.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/msg.rs#L175), [contract.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/contract.rs#L354) | Gno proxy upgrade surface corresponding to Union upgradable wrapper. |
| [access realm](../../access/README.md) / [access.gno](access.gno) | `QueryMsg::AccessManaged` | [msg.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/msg.rs#L238), [contract.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/contract.rs#L3206) | Replaced by access realm read surfaces instead of a nested ZKGM query. |
| [Pausable](admin.gno) | `QueryMsg::Pausable` | [msg.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/msg.rs#L240), [contract.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/contract.rs#L3207) | Gno exposes pause control, but no separate pause query wrapper. |

## Implementation-Level Union Differences

The surface index above maps public messages and queries. The table below tracks
verified implementation branches where the Gno v1 implementation intentionally
uses a different runtime model or currently leaves a Union branch unsupported.

| Area | Gno behavior | Union reference | Status |
| --- | --- | --- | --- |
| Market-maker settlement | Current code has fallback plumbing such as `ACK_ERR_ONLY_MAKER`, but Union market-maker settlement is not implemented as a supported feature. This includes native maker fills, solver-backed `TOKEN_ORDER_KIND_SOLVE`, and the zero-address burn sentinel used in ack settlement. | [relayer maker fill](https://github.com/unionlabs/union/blob/d91c5e94354e15801bd5f82dc658eae3b79f2dad/cosmwasm/app/ucs03-zkgm/src/contract.rs#L1791-L1860), [solver maker fill](https://github.com/unionlabs/union/blob/d91c5e94354e15801bd5f82dc658eae3b79f2dad/cosmwasm/app/ucs03-zkgm/src/contract.rs#L1863-L1913), [burn sentinel ack branch](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/contract.rs#L1030-L1042), [burn address helper](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/contract.rs#L3211-L3215) | Not implemented; `QueryMsg::GetBurnAddress` is marked `-` because its corresponding burn-sentinel branch is also missing. |
| Eureka calls | [verifyCall](v1/call.gno), [acknowledgeCall](v1/call.gno), and [timeoutCall](v1/call.gno) reject eureka mode or leave it as a no-op. | [timeout eureka forwarding](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/contract.rs#L679-L680), [ack eureka forwarding](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/contract.rs#L1164-L1165), [eureka reply handling](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/contract.rs#L2624-L2630) | Unsupported. |
| Token minter contract | [voucher.gno](v1/voucher.gno) keeps GRC20 voucher handles and ledger capability in proxy-owned state instead of calling a separate token-minter contract. | [minter instantiate](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/contract.rs#L65-L92), [token minter code id](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/msg.rs#L35) | Intentional Gno state model difference; explains `GetMinter`, `MigrateMinter`, and code-id rows. |
| Token order v1 | [dispatch.gno](v1/dispatch.gno) accepts `OP_TOKEN_ORDER` version byte `0x02` only. | [contract.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/contract.rs#L2751-L2764) | Token order v1 is not supported; this aligns with the v1 balance/migration rows above. |
