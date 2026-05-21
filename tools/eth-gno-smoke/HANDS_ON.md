# ETH/Gno Smoke Hands-On Guide

This guide explains how the local ETH/Gno smoke harness behaves, what data it
generates, and how each scenario validates the result.

The harness is intentionally local-only. It uses `gnodev`, `anvil`, `gnokey`,
`cast`, `solc`, `jq`, and a minimal Solidity commitment map. It does not depend
on Union Voyager, external EVM RPCs, Union deployments, or Union devnets.

## Quick Start

Run the full local smoke:

```sh
make test-eth-gno-smoke
```

Run each side separately:

```sh
make test-gno-to-eth-smoke
make test-eth-proof-fixture-smoke
make test-eth-to-gno-smoke
make test-eth-to-gno-success-smoke
```

The `Makefile` targets call the two dispatchers, which can also be run directly:

```sh
tools/eth-gno-smoke/smoke.sh all
tools/eth-gno-smoke/fixture.sh eth-proof
```

Generated fixtures are committed under each scenario folder:

```text
tools/eth-gno-smoke/scenarios/gno-to-eth/fixture.json
tools/eth-gno-smoke/scenarios/eth-proof/fixture.json
tools/eth-gno-smoke/scenarios/eth-to-gno-error/fixture.json
tools/eth-gno-smoke/scenarios/eth-to-gno-success/fixture.json
```

Re-running the smoke should leave these files unchanged in a clean environment.

## Gno to ETH

Scenario: `scenarios/gno-to-eth/`, run with `smoke.sh gno-to-eth`.

Purpose: prove that a Gno ZKGM send produces packet metadata and a batch packet
commitment that an ETH-side consumer can use.

Flow:

1. Start a local `gnodev` chain.
2. Import the deterministic smoke key.
3. Run `scenarios/gno-to-eth/send_packet.gno`.
4. Open an in-process mock IBC channel.
5. Send a ZKGM `OP_CALL` packet.
6. Print the packet fields and commitment data.
7. Write `scenarios/gno-to-eth/fixture.json`.

The runner derives:

```text
packet_hash = core.CommitPacket(packet)
batch_hash  = core.CommitPackets([]core.Packet{packet})
batch_path  = core.BatchPacketsPath(batch_hash)
value       = core.COMMITMENT_MAGIC
```

Validation:

- `batch_hash` must equal `packet_hash` for the single-packet batch.
- `commitment_value_hex` must equal `COMMITMENT_MAGIC`.
- The fixture is regenerated deterministically.

The runner does not submit anything to ETH. It captures the exact packet and
commitment data an ETH-side proof generator or relayer would need.

## ETH Proof Fixture

Scenario: `scenarios/eth-proof/`, run with `fixture.sh eth-proof`.

Purpose: prove that local EVM storage commitments can be converted into the
Union `StorageProof` byte format accepted by the Gno state-lens/ics23/mpt
adapter.

Flow:

1. Start local `anvil`.
2. Compile and deploy `scenarios/eth-proof/CommitmentMap.sol`.
3. Write one or more `bytes32 -> bytes32` commitments.
4. Compute each Solidity mapping storage slot.
5. Fetch `eth_getProof` for each slot.
6. Encode each proof with `cmd/encode-storage-proof`.
7. Write the selected fixture JSON.

The minimal contract is:

```solidity
mapping(bytes32 => bytes32) public commitments;
```

The storage slot matches Solidity's mapping convention:

```text
storage_slot = keccak256(abi.encode(commitment_path, uint256(0)))
```

The proof encoder writes the format consumed by
`gno.land/p/core/ethereum/storage.DecodeProof`:

```text
key   = U256 little-endian 32 bytes
value = U256 little-endian 32 bytes
proof = u64 count + repeated (u64 byte_length + rlp_node_bytes)
```

Default output:

```text
tools/eth-gno-smoke/scenarios/eth-proof/fixture.json
```

When the `eth-to-gno-*` scenarios call it, they override the output so the proof
lands in the calling scenario's own `fixture.json`.

## ETH to Gno

Scenarios: `scenarios/eth-to-gno-error/` (`smoke.sh eth-to-gno`) and
`scenarios/eth-to-gno-success/` (`smoke.sh eth-to-gno-success`).

Purpose: prove that Gno can verify local ETH storage proofs and receive an
ETH-originated packet through `core.PacketRecv`.

Flow of the error scenario:

1. Start a local `gnodev` chain on the ETH-to-Gno smoke port.
2. Run `scenarios/eth-to-gno-error/fixture_inputs.gno`.
3. Derive the counterparty connection ack path/value.
4. Derive the counterparty channel ack path/value.
5. Derive the packet batch commitment path/value.
6. Store all three commitments in local `anvil`.
7. Fetch and encode an ETH storage proof for each commitment.
8. Render `scenarios/eth-to-gno-error/recv.gno.tmpl` with the storage root and
   proof bytes.
9. Submit the rendered script with `gnokey maketx run`.
10. Verify packet receive, acknowledgement, and duplicate receive behavior.

The rendered Gno script:

- registers the mock light client,
- creates the state-lens/ics23/mpt client with the ETH `storage_root`,
- opens the local connection using the ETH connection ack proof,
- opens the local channel using the ETH channel ack proof,
- submits `core.PacketRecv` using the ETH packet commitment proof,
- submits the same `PacketRecv` again to verify replay behavior.

Validation:

- the transaction must succeed,
- a `PacketRecv` event must be emitted,
- a `WriteAck` event must be emitted,
- `core.HasPacketReceipt(cross, packet)` must be true,
- `core.HasAcknowledgement(cross, packet)` must be true,
- duplicate receive must keep the same acknowledgement hash.

The error scenario's packet payload reaches `WriteAck` with a `UNIVERSAL_ERROR`
acknowledgement, which exercises the core receive path, state-lens proof
verification, acknowledgement write, and duplicate guard. The success scenario
drives a packet that reaches a success acknowledgement and additionally asserts
that the mock receiver was called exactly once with the expected sender and
calldata.

## Artifacts

`scenarios/gno-to-eth/fixture.json` contains:

- packet fields,
- packet hash,
- batch hash,
- Gno batch commitment path,
- commitment value.

`scenarios/eth-proof/fixture.json` contains:

- local EVM contract address,
- storage slot,
- storage root,
- one encoded proof.

`scenarios/eth-to-gno-error/fixture.json` and
`scenarios/eth-to-gno-success/fixture.json` contain:

- connection ack proof,
- channel ack proof,
- packet commitment proof,
- shared storage root used by the rendered receive script.

## Troubleshooting

If `anvil` is already running on the configured RPC URL, stop it before running
the smoke or choose isolated values:

```sh
ANVIL_PORT=18545 ANVIL_RPC_URL=http://127.0.0.1:18545 make test-eth-to-gno-smoke
```

If `gnodev` is already using the default RPC port, use the ETH-to-Gno runner's
dedicated variables:

```sh
ETH_GNO_RECV_RPC_LISTENER=127.0.0.1:26659 \
ETH_GNO_RECV_RPC_URL=http://127.0.0.1:26659 \
ETH_GNO_RECV_RPC_ENDPOINT=tcp://127.0.0.1:26659 \
make test-eth-to-gno-smoke
```

If `vendor` fails with a `.git/modules` lock error inside a sandboxed
environment, run the make target outside the sandbox. The target updates
submodule worktree metadata before launching the smoke.
