# Implementation Specs

These specifications describe the current behavior implemented in this
repository. They are not roadmap documents.

| Spec | Scope |
|------|-------|
| [Architecture](architecture.md) | System topology, actors, state ownership, authorization boundaries, and lifecycle sequences |
| [IBC v1 Core](ibc-v1-core.md) | Clients, connections, channels, packets, acknowledgements, and core events |
| [ZKGM v1 App](zkgm-v1.md) | ZKGM proxy, v1 implementation, instructions, SendRaw, batches, forwards, and token orders |
| [Light Clients](light-clients.md) | v1 light-client adapter contract, CometBLS, and state-lens ICS23 MPT |
| [Event Catalog](events.md) | IBC/ZKGM event types, attributes, stability, and encoding rules |
| [Native Stdlibs and Toolchain](native-stdlibs-toolchain.md) | Pinned Gno toolchain setup, temporary local stdlib overlay, native bindings, and calibrated gas |

## Maintenance Rules

- Update the relevant implementation spec in the same change that modifies
  externally observable behavior.
- Keep proposal language out of implementation specs. If a design is not in the
  current code path, keep it out of `docs/specs`.
- Prefer links to source files, tests, fixture generators, or runbooks over
  repeating implementation details that are likely to drift.
