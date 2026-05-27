# Light Clients Spec

This document describes the current v1 light-client adapter model and the
implemented light clients under
[gno.land/r/core/ibc/v1/lightclients](../../gno.land/r/core/ibc/v1/lightclients)
and [gno.land/p/core/ibc/lightclients](../../gno.land/p/core/ibc/lightclients).

## Adapter Contract

IBC core interacts with light clients through realm adapters. Adapters are
registered by client type and are responsible for translating core calls into
client-specific state transitions and proof verification.

Adapter responsibilities include:

- client creation
- client update
- client status reporting
- membership proof verification
- non-membership proof verification
- optional force update support

Mutating adapter entry points are core-only. Proof verification paths must
reject inactive clients before decoding or verifying proof bytes. This protects
both membership and non-membership verification from frozen or expired clients.

## CometBLS

The CometBLS client type is `cometbls`.

The stateless package under
[gno.land/p/core/ibc/lightclients/cometbls](../../gno.land/p/core/ibc/lightclients/cometbls)
contains validation, protobuf encoding/decoding, header handling,
misbehaviour handling, and proof verification helpers.

The realm adapter under
[gno.land/r/core/ibc/v1/lightclients/cometbls](../../gno.land/r/core/ibc/v1/lightclients/cometbls)
owns persisted client state and consensus state. It supports create, update,
status, membership verification, non-membership verification, and deployer-only
force updates through IBC core.

Status is reported as active, frozen, or expired. Misbehaviour freezes the
client. Expiration is determined from the client state and current block time.
Membership and non-membership verification reject any non-active status before
proof decoding.

## State-Lens ICS23 MPT

The state-lens ICS23 MPT adapter lives under
[gno.land/r/core/ibc/v1/lightclients/statelensics23mpt](../../gno.land/r/core/ibc/v1/lightclients/statelensics23mpt).

It verifies storage membership and non-membership proofs against state derived
from a referenced L1 client. Its status mirrors the referenced L1 client status;
if the referenced L1 client is missing or inactive, the state-lens client is not
usable for proof verification.

The update path verifies the L2 consensus state through the L1 membership proof
before persisting the derived state. Membership and non-membership verification
reject inactive status before proof decoding.

During update, the adapter verifies membership of
`ConsensusStatePath(L2ClientID, L2Height)` against the referenced L1 client at
`L1Height`. The verified value is the Keccak hash of the encoded L2 consensus
state carried in the header.

## Implementation Rules

- New v1 adapters must guard `VerifyMembership` and `VerifyNonMembership`
  against inactive status before decoding proofs.
- Adapter-level checks do not replace inner-client checks. Inner clients should
  still enforce status conditions they can determine without caller context.
- Tests for new adapters should cover frozen or expired clients for both
  membership and non-membership verification.

## Maintenance Notes

This spec should track the current adapter contract and implemented light-client
behavior only. Keep historical planning notes out of committed implementation
specs.
