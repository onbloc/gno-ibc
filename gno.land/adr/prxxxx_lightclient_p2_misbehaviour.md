# Light Client P2 Misbehaviour Entrypoint

## Context

Union core exposes a misbehaviour entrypoint that rejects inactive clients,
passes the client message to the light client, stores the returned frozen client
state bytes, updates the client-state commitment, and emits a `Misbehaviour`
event.

gno-ibc stores light clients as objects. The existing lightclient interface
already has `Misbehaviour`, but it returns an opaque `types.ClientState` object,
while core needs encoded bytes for queries and Union-compatible commitments.

## Decision

Keep `lightclient.Interface.Misbehaviour` returning `types.ClientState` to avoid
breaking the object-oriented client API. Add an optional
`lightclient.ClientStateProvider` extension with `ClientStateBytes()`, and have
core call it after successful misbehaviour verification.

Add `types.MsgMisbehaviour` and a core `Misbehaviour(cur realm, msg)` entrypoint.
The entrypoint:

- loads the client and rejects inactive status before calling the light client;
- calls `c.lightClient.Misbehaviour(caller, msg.ClientMessage, msg.Relayer)`;
- reads current encoded client state bytes from `ClientStateProvider`;
- saves the client state mirror and commitment;
- emits `Misbehaviour` with `client_id`.

CometBLS and StateLens ICS23 MPT implement `ClientStateProvider`. CometBLS uses
the provider to expose the frozen client state after misbehaviour succeeds.

## Alternatives Considered

Changing `Misbehaviour` to return bytes directly was rejected because it would
force a broader interface break and make the object-state return less useful for
Gno light clients.

Reusing `InitialStateProvider.InitialClientStateBytes()` after misbehaviour was
rejected because it would blur creation-time state with current state. A separate
provider makes the side effect explicit.

Skipping core persistence for clients without an encoder was rejected because
Union's observable behavior is the stored frozen state and commitment. Core now
panics if a successful misbehaviour call cannot provide encoded state bytes.

## Consequences

The core misbehaviour path is now Union-compatible for active gating, state
mirror persistence, commitments, and event attributes. Light clients that support
misbehaviour must also expose current encoded client state bytes.
