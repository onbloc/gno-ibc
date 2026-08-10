from __future__ import annotations

import json

from . import codec
from .chain import Chain
from .constants import *


class Checks:
    def __init__(self, chain: Chain):
        self.chain = chain

    def verify_failed_work(self, baseline: int | None = None, voyager=None) -> None:
        v = voyager or self.chain.v
        want = self.chain.state["failed_work"]["final"] if baseline is None else baseline
        repaired = set(self.chain.state["failed_work"]["repaired"])
        ids = [int(row["id"]) for row in v.failed_rows()]
        if want and (not ids or want > max(ids)):
            raise RuntimeError("saved failed-work ID is ahead of Voyager queue")
        got = max((item for item in ids if item not in repaired), default=0)
        if want is not None and got != want:
            raise RuntimeError(f"Voyager recorded new failed work: {got}, expected {want}")

    def verify_evm_commitment_cleared(self, packet_hash: str) -> None:
        encoded = self.chain.cast("abi-encode", "f(uint256,bytes32)", "4", packet_hash)
        key = self.chain.cast("keccak", encoded)
        value = self.chain.cast("call", self.chain.c["EVM_IBC_HANDLER"].lower(),
                          "commitments(bytes32)(bytes32)", key).split()[0]
        if value.lower() != CLEARED_COMMITMENT:
            raise RuntimeError("EVM packet commitment is still active")

    def verify_clients(self) -> None:
        clients = self.chain.state["clients"]
        checks = (
            ("gno_union", self.chain.c["GNO_CHAIN_ID"], self.chain.c["UNION_CHAIN_ID"], "cometbls", "ibc-gno"),
            ("union_gno", self.chain.c["UNION_CHAIN_ID"], self.chain.c["GNO_CHAIN_ID"], "gno", "ibc-cosmwasm"),
            ("union_evm", self.chain.c["UNION_CHAIN_ID"], self.chain.c["EVM_CHAIN_ID"], "trusted/evm/mpt", "ibc-cosmwasm"),
            ("evm_union", self.chain.c["EVM_CHAIN_ID"], self.chain.c["UNION_CHAIN_ID"], "cometbls", "ibc-solidity"),
            ("gno_evm", self.chain.c["GNO_CHAIN_ID"], self.chain.c["EVM_CHAIN_ID"], "state-lens/ics23/mpt", "ibc-gno"),
            ("evm_gno", self.chain.c["EVM_CHAIN_ID"], self.chain.c["GNO_CHAIN_ID"], "proof-lens", "ibc-solidity"),
        )
        for name, chain, counterparty, client_type, interface in checks:
            client_id = clients[name]
            self.chain.v.assert_client_relation(
                chain, client_id, client_type, interface, counterparty)
        for side, name, l1, l2, l2_chain in (
            (self.chain.c["GNO_CHAIN_ID"], "gno_evm", "gno_union", "union_evm", self.chain.c["EVM_CHAIN_ID"]),
            (self.chain.c["EVM_CHAIN_ID"], "evm_gno", "evm_union", "union_gno", self.chain.c["GNO_CHAIN_ID"]),
        ):
            response = self.chain.v.json("rpc", "client-state", side, str(clients[name]), "--decode")
            state = response.get("state", response)
            if isinstance(state, dict) and "@value" in state:
                state = state["@value"]
            if (int(state["l1_client_id"]) != clients[l1] or
                    int(state["l2_client_id"]) != clients[l2] or
                    state["l2_chain_id"] != l2_chain):
                raise RuntimeError(f"Lens client relation mismatch: {side}/{clients[name]}")

    def observe_erc20(self, packet: dict, want_success: bool = True, voyager=None) -> dict:
        v = voyager or self.chain.v

        recv, write = self._await_gno_recv_write(packet, v)
        success, ack_log = self._verify_cross_chain_ack(packet, write, want_success, v)
        self.verify_evm_commitment_cleared(packet["packet_hash"])
        deltas = self._verify_balance_deltas(packet, success)
        self.verify_failed_work(packet["failed_work_baseline"], voyager=v)

        return {"outcome": "success" if success else "failure", "token": packet["token"],
                "packet_hash": packet["packet_hash"], "commitment_cleared": True,
                "transactions": {"mint": packet["mint_tx"], "approve": packet["approve_tx"],
                                 "send": packet["tx"], "gno_receive": recv["tx"],
                                 "gno_write_ack": write["tx"],
                                 "evm_ack": ack_log["transactionHash"]},
                "balance_deltas": deltas}

    def _await_gno_recv_write(self, packet: dict, v) -> tuple[dict, dict]:
        events = self.chain.wait_events(["PacketRecv", "WriteAck"],
                                        {"packet_hash": packet["packet_hash"]}, 2, voyager=v)
        recv = [item for item in events if item["type"] == "PacketRecv"]
        write = [item for item in events if item["type"] == "WriteAck"]
        if len(recv) != 1 or len(write) != 1 or recv[0]["tx"] != write[0]["tx"]:
            raise RuntimeError("Gno PacketRecv and WriteAck do not form one transaction")
        return recv[0], write[0]

    def _verify_cross_chain_ack(self, packet: dict, write: dict,
                                want_success: bool, v) -> tuple[bool, dict]:
        log = self.chain.wait_evm_log(
            packet["from_block"], [PACKET_ACK_TOPIC, self.chain.evm_channel_topic(),
                                   packet["packet_hash"]], "EVM PacketAck", voyager=v)
        decoded = json.loads(self.chain.cast("decode-abi", "f()(bytes)", log["data"], "--json"))[0]

        source_ack = codec.acknowledgement(write["attrs"])
        if source_ack.lower().removeprefix("0x") != decoded.lower().removeprefix("0x"):
            raise RuntimeError("cross-chain acknowledgement bytes differ")

        # ZKGM Ack is successful when the first ABI tag is 1.
        success = codec.acknowledgement_success(source_ack)
        if success != want_success:
            raise RuntimeError(f"acknowledgement success={success}, want {want_success}")
        return success, log

    def _verify_balance_deltas(self, packet: dict, success: bool) -> dict:
        after = {"sender": self.chain.token_balance(packet["token"], packet["sender"]),
                 "escrow": self.chain.token_balance(packet["token"], self.chain.c["EVM_ZKGM_CONTRACT"]),
                 "recipient": self.chain.voucher_balance(packet["voucher"], packet["recipient"])}
        deltas = {key: after[key] - packet["before"][key] for key in after}

        expected = int(packet["amount"])
        expected_deltas = ({"sender": -expected, "escrow": expected,
                            "recipient": expected // 10 ** max(int(packet["decimals"]) - 6, 0)} if success else
                           {"sender": 0, "escrow": 0, "recipient": 0})
        if deltas != expected_deltas:
            raise RuntimeError(f"unexpected packet balance deltas: {deltas}")
        return deltas
