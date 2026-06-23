# Union State-Lens ICS23/MPT Light Client Package

Pure package implementing the Union state-lens light client backed by ICS23/MPT
proofs.

This client verifies L2 commitments using an L1 light client reference held in
its client state. The core host owns the client id and routes through the shared
light-client interface; this package owns proof decoding, consensus extraction,
and state-lens verification.

## Files

- [client.gno](client.gno) contains the light-client object and interface
  methods.
- [types.gno](types.gno) defines the flattened client state, consensus state,
  and header shapes.
- [consensus.gno](consensus.gno) extracts L2 consensus state and validates
  commitment proof keys.
- [ethabi.gno](ethabi.gno) encodes and decodes client state, consensus state,
  and headers.

## Notes

Misbehaviour is intentionally unsupported for state-lens clients, matching the
current Union model.
