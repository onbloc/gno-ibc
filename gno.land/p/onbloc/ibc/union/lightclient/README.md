# Union Light Client Interface Package

Pure interface package for light clients installed behind the Union core host.

Core stores concrete light-client objects through `Interface`, while each
implementation owns its own client-state, consensus-state, header, proof, and
wire-format logic.

## Files

- [types.gno](types.gno) defines client status values and the light-client
  interface used by core.

## Implementations

- [cometbls/](cometbls/) implements the Union CometBLS client.
- [state_lens/ics23_mpt/](state_lens/ics23_mpt/) implements the state-lens
  ICS23/MPT client.
