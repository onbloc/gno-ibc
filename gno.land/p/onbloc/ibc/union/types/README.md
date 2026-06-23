# IBC Union Types Package

Pure package for IBC Union host types, message shapes, path helpers, and
commitment hashing.

Realm code imports this package for stable public data structures shared between
core, apps, light clients, and tests. Constructors are provided for foreign
realms that need to allocate values across Gno realm boundaries.

## Files

- [types.gno](types.gno), [client.gno](client.gno),
  [connection.gno](connection.gno), [channel.gno](channel.gno), and
  [packet.gno](packet.gno) define ids, status values, and core IBC Union data
  structures.
- [msgs.gno](msgs.gno) and [msgs_handshake.gno](msgs_handshake.gno) define
  public message shapes.
- [path.gno](path.gno), [commit.gno](commit.gno), and
  [keccak.gno](keccak.gno) build Union storage paths and commitment hashes.
- [abi.gno](abi.gno) holds ABI schemas used by commitment and packet encoding.
- [relayer_selectors.gno](relayer_selectors.gno) lists selectors wired into
  access control.
