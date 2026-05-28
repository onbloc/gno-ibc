# Salt, Path, and Call

This page covers salt derivation, path packing, and the `OP_CALL` instruction.
All three are used by other opcodes too, so this is the entry point for
understanding how ZKGM packets are addressed.

## Salt derivation

User sends derive the wire salt with:

```text
keccak256(abi_encode_params((sender, salt)))
```

`DeriveSenderSalt` uses the raw UTF-8 bytes of the sender account string and
the raw user-supplied salt.

Batch children derive their salt with:

```text
keccak256(index_uint256_be || parent_salt)
```

Forward children derive their salt with `DeriveForwardSalt(parentSalt)`, which
hashes the parent salt and OR-masks `FORWARD_SALT_MAGIC` into the result.
`IsForwardedPacket` tests that marker when acknowledgements or timeouts return
from a forwarded child.

## Path packing

Channel paths are packed into a single `uint256` slot. The path helpers in the
stateless ZKGM package own this layout (see
[Wire Encoding](./wire-encoding.md#path-layout-uint256-packed-channel-ids-lsb-first)).
Forward execution dequeues channel hops from `Forward.Path` and uses
`UpdateChannelPath` to extend the current packet path.

## OP_CALL semantics

`verifyCall` rejects Eureka mode and requires `Call.Sender` to match the ZKGM
sender captured by `Send`.

`executeCall` decodes `Call.ContractAddress` as a receiver pkgpath, resolves
the registered receiver, computes
`PredictCallProxyAccount(path, destChannel, sender)`, and calls
`receiver.OnZkgm`.

Call outcomes map to acknowledgements as follows:

| Outcome | Result |
|---------|--------|
| Receiver panic | `PacketStatusSuccess` with `ACK_ERR_ONLY_MAKER`. |
| Receiver returns error | Failure `Ack` with the error message in `InnerAck`. |
| Receiver succeeds | Success `Ack` with empty `InnerAck`. |

Receiver panics are treated as recoverable: emitting `ACK_ERR_ONLY_MAKER`
inside a success-tagged ack lets a market maker still settle the call instead
of triggering a refund chain on the source side.

`acknowledgeCall` and `timeoutCall` are no-ops except that they reject Eureka
mode. Calls hold no escrow state, so there is nothing to refund.

`IntentRecv` reuses the dispatcher with `intent = true`. The current `OP_CALL`
execution path still calls `OnZkgm`. `OnIntentZkgm` is present in the
`Zkgmable` interface but is not invoked by the current `executeCall`. This is
current behavior, not a design contract.
