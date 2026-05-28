# Core Registration and Acknowledgement Authority

## Context

The v1 IBC core realm has two authority-sensitive surfaces:

- registration, which binds client types and port ids to implementations
- packet receipt state, which becomes evidence for duplicate receive and timeout handling

The previous model relied on caller convention. Apps could register arbitrary
port ids, test fixtures needed special-case client registration, proofless intent
receive wrote the same receipt as proven receive, and acknowledgements could be committed without a prior receipt.

## Decision

Use explicit authority boundaries:

- Make ordinary app and client registration self-registration only.
- Keep explicit deployer-only paths for loader-style registration.
- Route known production client registration through the owning light client realm, using explicit client type ownership where the type does not map mechanically to a realm path.
- Proofless intent receives do not write packet receipts.
- Acknowledgement writes require an existing packet receipt.

## Alternatives Considered

Hard-coding test fixture paths in core was rejected because production code should not know about test realms.

Deriving owner realms from client type strings was rejected because client types such as `state-lens/ics23/mpt` do not match their package paths.

Making all registration deployer-only was rejected because it hides normal ownership behind an admin path.

## Consequences

Core now separates self-registration from privileged loader registration. Apps cannot reserve foreign port ids through the ordinary path, and production client types cannot be registered by unrelated realms.

Intent receive remains a proofless fast path, but only proven receive creates packet receipt evidence. Acknowledgements can only be written for packets that have been received.
