# Union Core Proxy Realm

Upgradeable proxy realm for the Union IBC host.

The proxy keeps the stable package identity, access-managed public entrypoints,
app registry, persistent store, event emitters, query surface, and implementation
upgrade point. The installed implementation realm supplies the swappable IBC
client, connection, channel, packet, proof, batch, and app-registry logic behind
the `ICore` interface.

## Files

- [core.gno](core.gno) exposes packet lifecycle and proof entrypoints.
- [client.gno](client.gno), [connection.gno](connection.gno),
  [channel.gno](channel.gno), and [app.gno](app.gno) expose the public client,
  handshake, channel, and app-registration surfaces.
- [getters.gno](getters.gno) exposes read-only query helpers.
- [types.gno](types.gno) defines the proxy, implementation, getter, and store
  interfaces.
- [store.gno](store.gno) owns persistent core state.
- [upgrade.gno](upgrade.gno) registers and installs implementation realms.
- [access.gno](access.gno) and [errors.gno](errors.gno) define access selectors
  and error helpers.
- [emit.gno](emit.gno), [event.gno](event.gno), and
  [encoding.gno](encoding.gno) hold host event and wire helpers.
- [render.gno](render.gno) exposes the realm render surface.

## Implementation

The canonical implementation currently lives in [v1/](v1/). It registers itself
with the proxy from init and receives the proxy-owned store before delegated
entrypoints run.
