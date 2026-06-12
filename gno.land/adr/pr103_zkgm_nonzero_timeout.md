# ZKGM Non-Zero Timeout

## Context

ZKGM sends commit source-chain packets that are cleared by acknowledgement or timeout.
If a packet is never received, timeout is the only refund path for escrowed value.

The v1 core timeout path treats `TimeoutTimestamp == 0` as "not reached", and ZKGM
sends always use `timeoutHeight = 0`. A ZKGM packet with a zero timeout timestamp can
therefore create a packet commitment that cannot time out and may permanently lock
value. Forward instructions can create the same issue for child packets because the
forward operand supplies the child timeout timestamp.

## Decision

Reject `timeoutTimestamp == 0` at ZKGM's send chokepoint before packet commitment.
`Send` and `SendRaw` both funnel through `sendPacket`, so a single guard covers both
public send entry points.

Reject `Forward.TimeoutTimestamp == 0` in `buildForwardChild` before constructing or
committing a child packet. The forward path returns an error instead of panicking, so
`executeForward` converts malformed zero-timeout forwards into a clean receive
failure result.

Also reject `Forward.TimeoutTimestamp == 0` in `verifyForward`, which runs on the
sender's verify path. This fails the originating send tx immediately instead of
letting the relayer discover the malformed forward when `buildForwardChild` rejects it
at the next hop.

Do not change v1 core `PacketSend` or `BatchSend` in this PR.

## Alternatives Considered

A core-level guard in `PacketSend` and `BatchSend` was considered. It would provide
broader defense for future non-ZKGM apps, but it expands the blast radius into shared
core semantics and fixture paths that construct packets directly. This PR keeps the
fix at the ZKGM surfaces that create the lock.

Minimum or maximum timeout windows were considered. They are deferred because the
source send path currently does not have a nanosecond clock helper, while the ZKGM
rate-limit clock is seconds-based. Adding window bounds without first cleaning up
those units risks rejecting valid test fixtures or comparing incompatible units.

Inheriting or clamping a forward child timeout from the parent packet was rejected.
The parent timeout belongs to the previous hop, not the next hop, and silently
rewriting a malformed forward operand would hide the caller error.

## Consequences

ZKGM can no longer create unrecoverable zero-timeout source commitments through its
public send path or through forwarded child packets.

Future non-ZKGM apps can still commit zero-timeout packets directly through core until
a separate core-level hardening change is made.

Timeout window bounds remain a future hardening item. They should be introduced only
after the send path has a nanosecond clock and fixtures are migrated to realistic
nanosecond timeout values where needed.
