# IBC Union CometBLS Light Client Package

Pure package implementing the Union CometBLS light-client object used by the
core host.

The client stores client state and consensus states in the object instance. Core
routes membership, non-membership, header, creation, misbehaviour, timestamp,
height, chain-id, and status calls through the shared light-client interface.

## Files

- [client.gno](client.gno) contains the light-client object and interface
  methods.
- [client_state.gno](client_state.gno),
  [consensus_state.gno](consensus_state.gno), [header.gno](header.gno), and
  [misbehaviour.gno](misbehaviour.gno) define client message/state types.
- [codec.gno](codec.gno), [encoding.gno](encoding.gno), and
  [proto.gno](proto.gno) handle wire formats.
- [client_verify.gno](client_verify.gno) verifies CometBLS headers and
  ICS23 proof chains.
- [keys.gno](keys.gno), [types.gno](types.gno), [utils.gno](utils.gno), and
  [errors.gno](errors.gno) hold storage-key, helper, and sentinel definitions.

## Notes

Membership keys are derived through the current `["wasm",
makeStoreKey(owner, key)]` path. Fixture tests that only parse older proof bytes
are parser coverage, not full verification coverage.
