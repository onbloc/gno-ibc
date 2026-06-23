# Union UCS03-ZKGM Proxy Realm

Upgradeable proxy realm for the Union UCS03-ZKGM IBC application.

The proxy keeps the stable app identity, package path, persistent store, access
gates, receiver registry, voucher ledger capabilities, and admin surfaces. The
installed implementation realm supplies the swappable protocol logic behind the
`IApp` interface.

## Files

- [app.gno](app.gno) exposes the core-facing IBC app and intent app callbacks.
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

## Test Realms

- [testing/](testing/) contains mock receivers, scenario helpers, attack
  harnesses, real-CometBLS fixtures, and upgrade-specific test realms.
