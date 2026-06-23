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
- [store.gno](store.gno) owns persistent ZKGM state.
- [upgrade.gno](upgrade.gno) registers and installs implementation realms.
- [register.gno](register.gno) registers the proxy app and OP_CALL receivers.
- [admin.gno](admin.gno), [access.gno](access.gno), and
  [assert.gno](assert.gno) define admin selectors and gates.
- [transfer.gno](transfer.gno) exposes the user-facing `Send` wrapper.
- [voucher.gno](voucher.gno) owns wrapped GRC20 voucher handles and ledger
  capability access.
- [events.gno](events.gno) emits ZKGM proxy events.
- [gnokey_tx_queries_zkgm.md](gnokey_tx_queries_zkgm.md) records operational
  query examples.

## Implementation

- [v1/](v1/) is the canonical implementation realm registered by this proxy.

## IBC Union Spec Surface Index

The tables below use Union ZKGM `ExecuteMsg`, nested `IbcUnionMsg`,
`RestrictedExecuteMsg`, and `QueryMsg` variants as the row source. `-` means this
proxy does not expose a matching Gno public surface.

### Execute

| Gno surface | IBC Union surface | Reference | Notes |
| --- | --- | --- | --- |
| [App callbacks](app.gno) | `ExecuteMsg::IbcUnionMsg` | [msg.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/msg.rs#L91), [contract.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/contract.rs#L132) | Wrapper for core-driven app callbacks below. |
| - | `ExecuteMsg::InternalExecutePacket` | [msg.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/msg.rs#L94), [contract.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/contract.rs#L215) | CosmWasm self-call execution boundary; no Gno public surface. |
| - | `ExecuteMsg::InternalWriteAck` | [msg.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/msg.rs#L103), [contract.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/contract.rs#L237) | CosmWasm self-call ack boundary; no Gno public surface. |
| - | `ExecuteMsg::InternalBatch` | [msg.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/msg.rs#L106), [contract.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/contract.rs#L208) | CosmWasm self-call batch boundary; no Gno public surface. |
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
| [PredictWrappedToken](v1/predict.gno) | `QueryMsg::PredictWrappedToken` | [msg.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/msg.rs#L203), [contract.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/contract.rs#L3125) | Gno exposes the derivation as an impl function, not a proxy query. |
| [PredictWrappedTokenV2](v1/predict.gno) | `QueryMsg::PredictWrappedTokenV2` | [msg.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/msg.rs#L211), [contract.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/contract.rs#L3144) | Gno exposes the derivation as an impl function, not a proxy query. |
| - | `QueryMsg::GetMinter` | [msg.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/msg.rs#L220), [contract.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/contract.rs#L3163) | No Gno public query surface. |
| - | `QueryMsg::GetTokenBucket` | [msg.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/msg.rs#L221), [contract.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/contract.rs#L3167) | Store has an internal getter, but no public query surface. |
| - | `QueryMsg::GetChannelBalance` | [msg.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/msg.rs#L224), [contract.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/contract.rs#L3171) | No Gno public query surface. |
| - | `QueryMsg::GetChannelBalanceV2` | [msg.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/msg.rs#L229), [contract.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/contract.rs#L3182) | Store has an internal getter, but no public query surface. |
| - | `QueryMsg::GetConfig` | [msg.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/msg.rs#L235), [contract.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/contract.rs#L3201) | No matching Gno public query surface. |
| - | `QueryMsg::GetBurnAddress` | [msg.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/msg.rs#L236), [contract.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/contract.rs#L3205) | No Gno public query surface. |

### Admin

| Gno surface | IBC Union surface | Reference | Notes |
| --- | --- | --- | --- |
| [access realm](../../access/README.md) / [access.gno](access.gno) | `ExecuteMsg::AccessManaged` | [msg.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/msg.rs#L112), [contract.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/contract.rs#L276) | Replaced by the Gno access realm plus ZKGM selector gates. |
| [access realm](../../access/README.md) / [access.gno](access.gno) | `ExecuteMsg::Restricted` | [msg.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/msg.rs#L114), [contract.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/contract.rs#L279) | Replaced by the Gno access realm plus per-admin selector gates. |
| - | `RestrictedExecuteMsg::MigrateV1ToV2` | [msg.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/msg.rs#L143), [contract.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/contract.rs#L318) | CosmWasm storage migration; no Gno public surface. |
| [SetBucketConfig](admin.gno) | `RestrictedExecuteMsg::SetBucketConfig` | [msg.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/msg.rs#L148), [contract.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/contract.rs#L288) | Admin rate-limit bucket configuration. |
| - | `RestrictedExecuteMsg::MigrateMinter` | [msg.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/msg.rs#L155), [contract.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/contract.rs#L322) | CosmWasm minter migration; no Gno public surface. |
| [SetRateLimitDisabled](admin.gno) | `RestrictedExecuteMsg::SetRateLimitDisabled` | [msg.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/msg.rs#L162), [contract.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/contract.rs#L331) | Admin rate-limit enablement switch. |
| - | `RestrictedExecuteMsg::UpdateDummyCodeId` | [msg.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/msg.rs#L166), [contract.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/contract.rs#L340) | CosmWasm code-id setting; no Gno public surface. |
| - | `RestrictedExecuteMsg::UpdateCwAccountCodeId` | [msg.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/msg.rs#L169), [contract.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/contract.rs#L347) | CosmWasm code-id setting; no Gno public surface. |
| [Pausable](admin.gno) | `RestrictedExecuteMsg::Pausable` | [msg.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/msg.rs#L173), [contract.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/contract.rs#L357) | Admin pause/unpause wrapper. |
| [UpdateImpl](upgrade.gno) | `RestrictedExecuteMsg::Upgradable` | [msg.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/msg.rs#L175), [contract.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/contract.rs#L354) | Gno proxy upgrade surface corresponding to Union upgradable wrapper. |
| [access realm](../../access/README.md) / [access.gno](access.gno) | `QueryMsg::AccessManaged` | [msg.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/msg.rs#L238), [contract.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/contract.rs#L3206) | Replaced by access realm read surfaces instead of a nested ZKGM query. |
| [Pausable](admin.gno) | `QueryMsg::Pausable` | [msg.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/msg.rs#L240), [contract.rs](https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/app/ucs03-zkgm/src/contract.rs#L3207) | Gno exposes pause control, but no separate pause query wrapper. |
