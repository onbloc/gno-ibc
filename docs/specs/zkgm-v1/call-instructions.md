# Salt and Path Derivation

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
hashes the parent salt and applies `FORWARD_SALT_MAGIC`. `IsForwardedPacket`
tests that marker when acknowledgements or timeouts return from a forwarded
child.

Channel paths are packed into `uint256` slots by the path helpers in the ABI
package. Forward execution dequeues channel hops from `Forward.Path` and uses
`UpdateChannelPath` to extend the current packet path.

## Call Instructions

`verifyCall` rejects Eureka mode and requires `Call.Sender` to match the ZKGM
sender captured by `Send`.

`executeCall` decodes `Call.ContractAddress` as a receiver pkgpath, resolves the
registered receiver, computes `PredictCallProxyAccount(path, destChannel,
sender)`, and calls `receiver.OnZkgm`.

Call outcomes map to acknowledgements as follows:

| Outcome | Result |
|---------|--------|
| Receiver panic | `PacketStatusSuccess` with `ACK_ERR_ONLY_MAKER`. |
| Receiver returns error | Failure `Ack` with the error message in `InnerAck`. |
| Receiver succeeds | Success `Ack` with empty `InnerAck`. |

`acknowledgeCall` and `timeoutCall` are no-ops except that they reject Eureka
mode. Calls have no escrow state to refund.

`IntentRecv` reuses the dispatcher with `intent = true`. The current
`OP_CALL` execution path still calls `OnZkgm`. `OnIntentZkgm` is present in the
interface but is not called by the current `executeCall` implementation.
