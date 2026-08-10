from __future__ import annotations

import hashlib
import json
import os
import re
import stat
import sys
import tempfile
import time
from pathlib import Path

from . import codec
from .chain import Chain
from .checks import Checks
from .constants import *
from .voyager import SCRIPT_DIR, VERSION, Voyager, operation, render_voyager


class Runner:
    def __init__(self, config: dict, scenarios: list[str], resume: bool):
        self.c = config
        self.scenarios = scenarios
        self.resume = resume
        self.v = Voyager(config, self.progress)
        self.artifacts = Path(config["E2E_ARTIFACT_DIR"])
        self.state_path = Path(config["E2E_STATE_FILE"])
        self.state = self.expected_state()
        self.packet = None

        if ({"gno-to-evm", "gno-to-evm-timeout-refund"} & set(scenarios) and
                config["GNO_RECIPIENT"] != GNO_SENDER):
            raise RuntimeError("Gno-to-EVM scenarios require the dev Gno sender")

        if resume:
            info = self.state_path.lstat()
            if (not stat.S_ISREG(info.st_mode) or self.state_path.is_symlink() or
                    stat.S_IMODE(info.st_mode) != 0o600):
                raise RuntimeError("resume state must be a regular mode 0600 file")
            try:
                saved = json.loads(self.state_path.read_text())
            except (OSError, json.JSONDecodeError) as error:
                raise RuntimeError(f"cannot load state: {error}") from error
            for key in ("voyager_revision", "chains", "evm_topology", "ports", "version"):
                if saved.get(key) != self.state[key]:
                    raise RuntimeError(f"saved topology does not match current {key}")
            self.state = saved

        self.chain = Chain(config, self.v, self.state)
        self.checks = Checks(self.chain)

    def expected_state(self) -> dict:
        return {
            "voyager_revision": self.c["UNION_VOYAGER_REVISION"],
            "chains": {"union": self.c["UNION_CHAIN_ID"], "evm": self.c["EVM_CHAIN_ID"],
                       "gno": self.c["GNO_CHAIN_ID"]},
            "evm_topology": {
                "chain_id": self.c["EVM_CHAIN_ID"],
                "ibc_handler": self.c["EVM_IBC_HANDLER"].lower(),
                "multicall": self.c["EVM_MULTICALL"].lower(),
                "zkgm": self.c["EVM_ZKGM_CONTRACT"].lower(),
                "cometbls_client_impl": self.c["EVM_COMETBLS_CLIENT_IMPL"].lower(),
                "proof_lens_client_impl": self.c["EVM_PROOF_LENS_CLIENT_IMPL"].lower(),
            },
            "ports": {"gno": self.c["GNO_ZKGM_PORT"],
                      "evm": self.c["EVM_ZKGM_CONTRACT"].lower()},
            "version": VERSION,
            "failed_work": {"baseline": 0, "final": None, "repaired": []},
            "clients": {}, "allowlists": {},
        }

    def progress(self, message: str) -> None:
        print("e2e: " + message, file=sys.stderr, flush=True)

    def evidence(self, name: str, value) -> None:
        target = self.artifacts / name
        data = json.dumps(value, indent=2, sort_keys=True) + "\n"
        if self.contains_secret(data):
            raise RuntimeError(f"artifact secret scan failed: {name}")

        self.write_artifact(target, data)

    def write_artifact(self, target: Path, data: str) -> None:
        descriptor, temporary = tempfile.mkstemp(prefix="." + target.name + ".", dir=target.parent)
        try:
            os.fchmod(descriptor, 0o600)
            with os.fdopen(descriptor, "w") as output:
                output.write(data)
                output.flush()
                os.fsync(output.fileno())

            os.replace(temporary, target)
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)

    def contains_secret(self, data: str) -> bool:
        if re.search(r"[A-Za-z][A-Za-z0-9+.-]*://[^/@\s]+:[^/@\s]+@", data):
            return True
        return any(self.c[name] and self.c[name] in data for name in (
            "TRUSTED_MPT_PRIVATE_KEY", "UNION_PRIVATE_KEY", "EVM_PRIVATE_KEY", "GNO_PRIVATE_KEY",
            "RELAYER_EMPTY_PRIVATE_KEY", "RELAYER_OFFLINE_PRIVATE_KEY", "RELAYER_RECOVERY_PRIVATE_KEY"))

    def save_state(self) -> None:
        self.evidence(self.state_path.name, self.state)

    def run(self) -> None:
        if self.state_path != self.artifacts / "state.json":
            raise RuntimeError("E2E_STATE_FILE must be E2E_ARTIFACT_DIR/state.json")
        if self.artifacts.resolve() in (SCRIPT_DIR.resolve(), SCRIPT_DIR.parent.parent.resolve()):
            raise RuntimeError("unsafe E2E_ARTIFACT_DIR")
        if not self.resume and self.state_path.exists():
            raise RuntimeError("state file already exists; use a fresh artifact directory")

        marker = self.artifacts / ".union-channel-e2e-artifacts"
        if self.artifacts.exists():
            if self.artifacts.is_symlink() or not self.artifacts.is_dir():
                raise RuntimeError("existing artifact directory is not owned by this runner")
            if marker.read_text().strip() != "union-channel-e2e-artifacts":
                raise RuntimeError("existing artifact directory is not owned by this runner")
        else:
            self.artifacts.mkdir(parents=True)
            marker.write_text("union-channel-e2e-artifacts\n")
            marker.chmod(0o600)

        self.artifacts.chmod(0o700)
        plain, proof = self.allowlists() if self.resume else ([], [])
        rendered = render_voyager(self.c, plain, proof)
        failed = False

        try:
            self.progress("Voyager: starting")
            self.v.start(rendered)
            self.progress("Voyager: ready")

            self.progress("channel topology: started")
            self.topology()
            self.progress("channel topology: passed")

            methods = {
                "forged-proof-rejection": self.forged_proof_rejection,
                "erc20-to-gno": self.erc20_to_gno,
                "amount-boundaries": self.amount_boundaries,
                "gno-to-evm": self.gno_to_evm,
                "relayer-insufficient-balance-failover": self.relayer_insufficient_balance_failover,
                "relayer-offline-failover": self.relayer_offline_failover,
                "relayer-balance-recovery": self.relayer_balance_recovery,
                "evm-to-gno-timeout-refund": self.evm_to_gno_timeout_refund,
                "gno-to-evm-timeout-refund": self.gno_to_evm_timeout_refund,
            }

            for name in self.scenarios:
                self.progress(f"scenario {name}: started")
                try:
                    methods[name]()
                except BaseException as error:
                    self.progress(f"scenario {name}: failed: {error}")
                    raise
                self.progress(f"scenario {name}: passed")
        except BaseException:
            failed = True
            raise
        finally:
            if failed:
                logs = self.v.logs()
                if logs and not self.contains_secret(logs):
                    self.write_artifact(self.artifacts / "voyager.log", logs)
            self.v.close()

    def topology(self) -> None:
        if self.resume:
            self.verify_topology()
            self.checks.verify_failed_work()
            return

        c = self.c
        baseline = self.v.failed_work()
        self.state["failed_work"]["baseline"] = baseline
        reserved = self.v.next_id(c["EVM_CHAIN_ID"], "client")
        self.v.restart(render_voyager(c, [reserved], [reserved + 1]))

        evm_from = self.v.latest_height(c["EVM_CHAIN_ID"], True)
        self.progress("channel topology: indexing Union and Gno")
        self.v.index(c["UNION_CHAIN_ID"])
        self.v.index(c["GNO_CHAIN_ID"])

        self.progress("channel topology: creating clients")
        clients = self.state["clients"]
        repair = {"failed_baseline": baseline, "repaired": self.state["failed_work"]["repaired"]}
        clients["gno_union"] = self.v.create_client(
            c["GNO_CHAIN_ID"], c["UNION_CHAIN_ID"], "cometbls", "ibc-gno", **repair)
        clients["union_gno"] = self.v.create_client(
            c["UNION_CHAIN_ID"], c["GNO_CHAIN_ID"], "gno", "ibc-cosmwasm", **repair)
        clients["union_evm"] = self.v.create_client(
            c["UNION_CHAIN_ID"], c["EVM_CHAIN_ID"], "trusted/evm/mpt", "ibc-cosmwasm", **repair)
        clients["evm_union"] = self.v.create_client(
            c["EVM_CHAIN_ID"], c["UNION_CHAIN_ID"], "cometbls", "ibc-solidity", **repair)
        if clients["evm_union"] != reserved:
            raise RuntimeError("EVM client allocation changed")
        clients["gno_evm"] = self.v.create_client(
            c["GNO_CHAIN_ID"], c["EVM_CHAIN_ID"], "state-lens/ics23/mpt", "ibc-gno",
            config={"l1_client_id": clients["gno_union"], "host_chain_id": c["GNO_CHAIN_ID"],
                    "l2_client_id": clients["union_evm"], "timestamp_offset": 88,
                    "state_root_offset": 0, "storage_root_offset": 32},
            height=self.v.client_height(c["UNION_CHAIN_ID"], clients["union_evm"]),
            **repair,
        )
        clients["evm_gno"] = self.v.create_client(
            c["EVM_CHAIN_ID"], c["GNO_CHAIN_ID"], "proof-lens", "ibc-solidity",
            config={"l1_client_id": clients["evm_union"], "host_chain_id": c["EVM_CHAIN_ID"],
                    "l2_client_id": clients["union_gno"], "timestamp_offset": 24},
            height=self.v.client_height(c["UNION_CHAIN_ID"], clients["union_gno"]),
            **repair,
        )
        if clients["evm_gno"] != reserved + 1:
            raise RuntimeError("EVM Proof Lens allocation changed")

        self.progress("channel topology: indexing EVM")
        self.v.index(c["EVM_CHAIN_ID"], evm_from)

        next_evm = self.v.next_id(c["EVM_CHAIN_ID"], "client")
        plain, proof = [], []
        for item in range(1, next_evm):
            info = self.v.client_info(c["EVM_CHAIN_ID"], item)
            (proof if info["client_type"] == "proof-lens" else plain).append(item)
        self.state["allowlists"] = {
            "plain": ",".join(map(str, plain)), "proof_lens": ",".join(map(str, proof))}
        self.v.restart(render_voyager(c, plain, proof))
        self.checks.verify_clients()

        connections = {
            "gno": self.v.next_id(c["GNO_CHAIN_ID"], "connection"),
            "evm": self.v.next_id(c["EVM_CHAIN_ID"], "connection"),
        }
        self.state["connections"] = connections
        self.v.submit(operation(c["EVM_CHAIN_ID"], "connection_open_init", {
            "client_id": clients["evm_gno"], "counterparty_client_id": clients["gno_evm"]}))
        self.wait_handshake("connection", connections)

        channels = {
            "gno": self.v.next_id(c["GNO_CHAIN_ID"], "channel"),
            "evm": self.v.next_id(c["EVM_CHAIN_ID"], "channel"),
        }
        self.state["channels"] = channels
        gno_port = self.chain.gno_port_topic()
        self.v.submit(operation(c["GNO_CHAIN_ID"], "channel_open_init", {
            "port_id": gno_port, "counterparty_port_id": c["EVM_ZKGM_CONTRACT"].lower(),
            "connection_id": connections["gno"], "version": VERSION}))
        self.wait_handshake("channel", channels)

        self.state["failed_work"]["final"] = baseline
        self.checks.verify_failed_work(baseline)
        self.save_state()

    def wait_handshake(self, kind: str, ids: dict) -> None:
        evidence = {}
        for side, chain in (("gno", self.c["GNO_CHAIN_ID"]), ("evm", self.c["EVM_CHAIN_ID"])):
            def query(chain=chain, item=ids[side]):
                state = self.v.ibc_state(chain, kind, item)
                if not state or str(state.get("state", "")).lower() != "open":
                    return None
                other = "evm" if side == "gno" else "gno"
                if kind == "connection":
                    clients = self.state["clients"]
                    want_client = clients[side + "_evm"] if side == "gno" else clients["evm_gno"]
                    want_counterparty = clients["evm_gno"] if side == "gno" else clients["gno_evm"]
                    if (int(state["client_id"]) != want_client or
                            int(state["counterparty_client_id"]) != want_counterparty or
                            int(state["counterparty_connection_id"]) != ids[other]):
                        raise RuntimeError(f"{chain} connection relation mismatch")
                else:
                    want_port = (self.c["EVM_ZKGM_CONTRACT"].lower() if side == "gno" else
                                 self.chain.gno_port_topic())
                    if (int(state["connection_id"]) != self.state["connections"][side] or
                            int(state["counterparty_channel_id"]) != ids[other] or
                            state["counterparty_port_id"].lower() != want_port.lower() or
                            state["version"] != VERSION):
                        raise RuntimeError(f"{chain} channel relation mismatch")
                return state

            evidence[side] = self.v.wait(query, f"{chain} {kind}-{ids[side]} OPEN")

        for side, value in evidence.items():
            self.evidence(f"{side}-{kind}.json", value)

    def verify_topology(self) -> None:
        if not self.state.get("connections") or not self.state.get("channels"):
            raise RuntimeError("saved topology is incomplete")

        self.checks.verify_clients()
        self.wait_handshake("connection", self.state["connections"])
        self.wait_handshake("channel", self.state["channels"])

    def erc20_to_gno(self) -> None:
        if self.packet:
            raise RuntimeError("ERC20 packet already submitted")

        self.packet = self.chain.submit_erc20()
        result = self.checks.observe_erc20(self.packet)
        self.packet["outcome"] = result["outcome"]

        self.evidence("packet-summary.json", result)

    def boundary_order(self, name: str, plan: dict, amount: str, kind: int,
                       want_success: bool) -> dict:
        prelude = self.chain.mint_approve_snapshot(plan, amount)

        packet = {**plan, **self.chain.send_token(plan, self.c["GNO_RECIPIENT"], amount, kind),
                  "amount": amount, "recipient": self.c["GNO_RECIPIENT"],
                  **prelude, "failed_work_baseline": self.state["failed_work"]["final"]}

        result = self.checks.observe_erc20(packet, want_success)
        return {"name": name, **result}

    def amount_boundaries(self) -> None:
        if not self.packet or self.packet.get("outcome") != "success":
            raise RuntimeError("amount boundaries require a successful ERC20 packet")

        overflow = self.chain.deploy_token("Union Overflow", "UOF", 6)
        overflow_plan = self.chain.prepare_token(overflow, 6, self.state["channels"]["gno"])
        first = self.boundary_order("max-plus-one-refund", overflow_plan,
                                    str(INT64_MAX + 1), 0, False)

        cumulative = self.chain.deploy_token("Union Cumulative", "UCM", 6)
        cumulative_plan = self.chain.prepare_token(cumulative, 6, self.state["channels"]["gno"])
        second = self.boundary_order("max-succeeds", cumulative_plan,
                                     str(INT64_MAX), 0, True)
        cumulative_plan["salt"] = "0x" + os.urandom(32).hex()
        third = self.boundary_order("cumulative-overflow-refund", cumulative_plan, "1", 1, False)

        if self.chain.voucher_balance(cumulative_plan["voucher"], self.c["GNO_RECIPIENT"]) != INT64_MAX:
            raise RuntimeError("cumulative overflow changed maximum voucher balance")
        registry_key = self.c["GNO_ZKGM_PORT"] + ".UE" + cumulative_plan["tag"][:6]
        supply = self.chain.voucher_supply(registry_key)
        if supply != INT64_MAX:
            raise RuntimeError("cumulative overflow changed maximum voucher supply")

        third["voucher_supply"] = str(supply)
        self.evidence("amount-boundaries.json", [first, second, third])

    def gno_order(self, name: str, wire_sender: str, plan: dict, kind: int,
                  want_success: bool) -> dict:
        from_block = self.chain.block()
        sent = self.chain.send_raw(self.chain.encode_native_order(wire_sender, plan, kind))

        receive = self.chain.wait_evm_receive(from_block, sent["packet_hash"])

        encoded_path = self.chain.cast("abi-encode", "f(uint256,bytes32)", "4", sent["packet_hash"])
        membership_path = self.chain.cast("keccak", encoded_path)
        membership_height = self.chain.union_membership_height(
            self.state["clients"]["union_gno"], sent["height"] + 1, membership_path)
        proof_height = self.v.client_height(
            self.c["EVM_CHAIN_ID"], self.state["clients"]["evm_gno"])
        if int(str(proof_height).split("-")[-1]) < membership_height:
            raise RuntimeError("EVM Proof Lens height does not cover Union membership proof")

        ack = self.chain.wait_gno_ack(sent["packet_hash"])
        if (ack["acknowledgement"].lower().removeprefix("0x") !=
                receive["acknowledgement"].lower().removeprefix("0x")):
            raise RuntimeError("Gno/EVM acknowledgement bytes differ")
        success = codec.acknowledgement_success(ack["acknowledgement"])
        if success != want_success:
            raise RuntimeError(f"{name} acknowledgement success={success}, want {want_success}")
        if not self.chain.gno_batch_commitment_cleared(sent["packet_hash"]):
            raise RuntimeError("Gno packet commitment is still active")

        self.checks.verify_failed_work()
        return {"name": name, "packet_hash": sent["packet_hash"], "source_tx": sent["tx"],
                "destination_tx": receive["tx"], "ack_tx": ack["tx"], "success": success,
                "wire_sender": wire_sender,
                "proof_client": self.state["clients"]["evm_gno"], "proof_height": proof_height,
                "membership_client": self.state["clients"]["union_gno"],
                "membership_height": membership_height,
                "membership_path": membership_path.removeprefix("0x")}

    def gno_to_evm(self) -> None:
        if not self.packet or self.packet.get("outcome") != "success":
            raise RuntimeError("Gno-to-EVM requires a successful ERC20 packet")

        self.v.index(self.c["EVM_CHAIN_ID"],
                     self.v.latest_height(self.c["EVM_CHAIN_ID"], True))

        plan = self.chain.wrapped_plan(self.state["channels"]["evm"])
        lifecycle_from = self.chain.block()
        proxy = self.chain.proxy_address()
        before = self.chain.native_balance(proxy)
        initialize = self.gno_order("initialize", self.c["GNO_RECIPIENT"], plan, 0, True)
        escrow = self.gno_order("escrow", self.c["GNO_RECIPIENT"], plan, 1, True)
        if self.chain.native_balance(proxy) - before != 2:
            raise RuntimeError("Gno proxy did not escrow both lifecycle sends")

        if self.chain.cast("code", plan["token"]) == "0x":
            raise RuntimeError("EVM wrapped token was not deployed")
        balance = self.chain.token_balance(plan["token"], plan["sender"])
        supply = self.chain.total_supply(plan["token"])
        if balance != 2 or supply != 2:
            raise RuntimeError("wrapped token initialize/escrow state is incorrect")
        creation_logs = self.chain.evm_logs(
            self.c["EVM_ZKGM_CONTRACT"], lifecycle_from,
            [CREATE_TOKEN_TOPIC, self.chain.evm_channel_topic(),
             codec.address_topic(plan["token"])])
        if len(creation_logs) != 1:
            raise RuntimeError("wrapped token creation event count is not one")

        self.chain.receipt("approve wrapped token", "send", plan["token"],
                     "approve(address,uint256)", self.c["EVM_ZKGM_CONTRACT"], "1",
                     "--private-key", self.c["EVM_PRIVATE_KEY"], "--json")
        receiver = GNO_TEST_RECEIVER
        receiver_before = self.chain.native_balance(receiver)
        proxy_before = self.chain.native_balance(proxy)
        from_block = self.chain.block()
        return_plan = {"token": plan["token"], "sender": plan["sender"], "voucher": "ugnot",
                       "metadata": "0x", "salt": "0x" + os.urandom(32).hex(), "decimals": 6}

        sent = self.chain.send_token(return_plan, receiver, "1", 2)
        events = self.chain.wait_events(["PacketRecv", "WriteAck"],
                                  {"packet_hash": sent["packet_hash"]}, 2)
        write = next(event for event in events if event["type"] == "WriteAck")
        ack_log = self.chain.wait_evm_log(from_block, [PACKET_ACK_TOPIC,
            self.chain.evm_channel_topic(), sent["packet_hash"]], "EVM PacketAck")
        evm_ack = json.loads(self.chain.cast("decode-abi", "f()(bytes)", ack_log["data"], "--json"))[0]

        if (codec.acknowledgement(write["attrs"]).lower().removeprefix("0x") !=
                evm_ack.lower().removeprefix("0x")) or not codec.acknowledgement_success(evm_ack):
            raise RuntimeError("UNESCROW did not receive a success acknowledgement")
        self.checks.verify_evm_commitment_cleared(sent["packet_hash"])
        if (self.chain.token_balance(plan["token"], plan["sender"]) != 1 or
                self.chain.total_supply(plan["token"]) != 1 or
                self.chain.native_balance(receiver) - receiver_before != 1 or
                self.chain.native_balance(proxy) - proxy_before != -1):
            raise RuntimeError("UNESCROW lifecycle balances are incorrect")
        unescrow = {"name": "unescrow", "packet_hash": sent["packet_hash"],
                    "source_tx": sent["tx"], "destination_tx": write["tx"],
                    "ack_tx": ack_log["transactionHash"], "success": True}

        invalid_plan = self.chain.wrapped_plan(self.state["channels"]["evm"] + 1)
        invalid_proxy_before = self.chain.native_balance(proxy)
        invalid_receiver_before = self.chain.native_balance(receiver)
        invalid = self.gno_order(
            "invalid-quote-refund", receiver, invalid_plan, 0, False)
        if (self.chain.native_balance(proxy) != invalid_proxy_before or
                self.chain.native_balance(receiver) - invalid_receiver_before != 1):
            raise RuntimeError("invalid quote packet was not fully refunded")
        if self.chain.gno_events(["PacketTimeout"], {"packet_hash": invalid["packet_hash"]}):
            raise RuntimeError("invalid quote packet unexpectedly timed out")

        self.evidence("gno-to-evm.json", {"lifecycle": [initialize, escrow, unescrow],
                                         "invalid_quote": invalid})

    def allowlists(self) -> tuple[list[int], list[int]]:
        return ([int(item) for item in self.state["allowlists"]["plain"].split(",") if item],
                [int(item) for item in self.state["allowlists"]["proof_lens"].split(",") if item])

    def restart_with_key(self, private_key: str) -> None:
        plain, proof = self.allowlists()
        config = dict(self.c)
        config["EVM_PRIVATE_KEY"] = private_key

        self.v.restart(render_voyager(config, plain, proof))

    def secondary(self) -> Voyager:
        plain, proof = self.allowlists()
        runtime = Voyager(self.c, self.progress)
        runtime.start(render_voyager(self.c, plain, proof))
        return runtime

    def relayer_insufficient_balance_failover(self) -> None:
        key = self.c["RELAYER_EMPTY_PRIVATE_KEY"]
        primary = self.chain.relayer_address(key)
        self.restart_with_key(key)

        secondary = None
        try:
            packet = self.chain.submit_erc20()
            self.chain.wait_events(["PacketRecv", "WriteAck"],
                             {"packet_hash": packet["packet_hash"]}, 2)

            stats = self.v.wait(lambda: (value if int((value := self.v.active_queue())["total"]) > 0
                                         else None), "active relayer queue")
            secondary = self.secondary()
            result = self.checks.observe_erc20(packet)

            ack_tx = result["transactions"]["evm_ack"]
            signer = self.chain.tx_sender(ack_tx)
            expected = self.chain.cast("wallet", "address", "--private-key", self.c["EVM_PRIVATE_KEY"]).lower()
            if signer != expected:
                raise RuntimeError("secondary relayer did not sign EVM acknowledgement")

            self.evidence("relayer-insufficient-balance-failover.json", {
                "primary_signer": primary, "primary_balance_wei": "0", "active_queue": stats,
                "secondary_signer": signer, "packet_hash": packet["packet_hash"],
                "secondary_completed": True, "transactions": result["transactions"]})
        finally:
            if secondary:
                secondary.close()
            self.restart_with_key(self.c["EVM_PRIVATE_KEY"])

    def relayer_offline_failover(self) -> None:
        key = self.c["RELAYER_OFFLINE_PRIVATE_KEY"]
        primary = self.chain.relayer_address(key)
        self.restart_with_key(key)
        plain, proof = self.allowlists()

        self.v.close()
        packet = self.chain.submit_erc20()

        secondary = Voyager(self.c, self.progress)
        try:
            secondary.start(render_voyager(self.c, plain, proof))
            # All direct observations are chain RPC reads; the secondary shares the queue DB.
            result = self.checks.observe_erc20(packet, voyager=secondary)
            signer = self.chain.tx_sender(result["transactions"]["evm_ack"])
            expected = self.chain.cast("wallet", "address", "--private-key", self.c["EVM_PRIVATE_KEY"]).lower()
            if signer != expected:
                raise RuntimeError("secondary relayer did not sign EVM acknowledgement")

            self.evidence("relayer-offline-failover.json", {
                "stopped_primary_signer": primary, "secondary_signer": signer,
                "packet_hash": packet["packet_hash"], "secondary_completed": True,
                "transactions": result["transactions"]})
        finally:
            secondary.close()
            self.v.start(render_voyager(self.c, plain, proof))

    def relayer_balance_recovery(self) -> None:
        key = self.c["RELAYER_RECOVERY_PRIVATE_KEY"]
        address = self.chain.relayer_address(key)
        self.restart_with_key(key)

        try:
            packet = self.chain.submit_erc20()
            self.chain.wait_events(["PacketRecv", "WriteAck"], {"packet_hash": packet["packet_hash"]}, 2)

            channel = self.chain.evm_channel_topic()
            pending_until = time.monotonic() + 2 * self.c["EVM_REFRESH"]
            while time.monotonic() < pending_until:
                if self.chain.evm_logs(self.c["EVM_IBC_HANDLER"], packet["from_block"],
                                 [PACKET_ACK_TOPIC, channel, packet["packet_hash"]]):
                    raise RuntimeError("zero-balance relayer unexpectedly acknowledged packet")
                time.sleep(self.c["POLL"])
            stats = self.v.wait(lambda: (value if int((value := self.v.active_queue())["total"]) > 0
                                         else None), "active relayer queue")

            fund = self.chain.receipt("fund relayer", "send", address, "--value", ONE_ETH_WEI,
                                "--private-key", self.c["EVM_PRIVATE_KEY"], "--json")
            result = self.checks.observe_erc20(packet)

            if self.chain.tx_sender(result["transactions"]["evm_ack"]) != address:
                raise RuntimeError("recovered relayer did not sign EVM acknowledgement")
            balance = int(self.chain.cast("balance", address))
            if balance <= 0:
                raise RuntimeError("funded relayer has no remaining balance")

            self.evidence("relayer-balance-recovery.json", {
                "primary_signer": address, "balance_before_wei": "0",
                "balance_after_wei": str(balance), "active_queue_before_funding": stats,
                "packet_hash": packet["packet_hash"], "active_retry_completed": True,
                "transactions": {**result["transactions"], "fund": fund["transactionHash"]}})
        finally:
            self.restart_with_key(self.c["EVM_PRIVATE_KEY"])

    def evm_to_gno_timeout_refund(self) -> None:
        cleanup = True

        try:
            pause_tx = self.chain.pause_gno(True)
            recorded_pause_tx = pause_tx

            packet = self.chain.submit_erc20(TIMEOUT_REFUND_SECONDS)
            channel = self.chain.evm_channel_topic()

            def timeout_query():
                logs = self.chain.evm_logs(
                    self.c["EVM_IBC_HANDLER"], packet["from_block"],
                    [[PACKET_TIMEOUT_TOPIC, PACKET_ACK_TOPIC], channel, packet["packet_hash"]])
                acknowledgements = [item for item in logs
                                    if item["topics"][0].lower() == PACKET_ACK_TOPIC]
                timeouts = [item for item in logs
                            if item["topics"][0].lower() == PACKET_TIMEOUT_TOPIC]
                if acknowledgements:
                    raise RuntimeError("EVM packet was acknowledged instead of timing out")
                if len(timeouts) > 1:
                    raise RuntimeError("multiple EVM PacketTimeout logs")
                return timeouts[0] if timeouts else None

            log = self.v.wait(timeout_query, "EVM PacketTimeout")

            self.checks.verify_evm_commitment_cleared(packet["packet_hash"])
            if self.chain.gno_events(["PacketRecv"], {"packet_hash": packet["packet_hash"]}):
                raise RuntimeError("paused Gno unexpectedly received packet")
            after = {"sender": self.chain.token_balance(packet["token"], packet["sender"]),
                     "escrow": self.chain.token_balance(packet["token"], self.c["EVM_ZKGM_CONTRACT"]),
                     "recipient": self.chain.voucher_balance(packet["voucher"], packet["recipient"])}
            deltas = {key: after[key] - packet["before"][key] for key in after}
            if deltas != {"sender": 0, "escrow": 0, "recipient": 0}:
                raise RuntimeError("EVM timeout did not fully refund balances")

            unpause_tx = self.chain.pause_gno(False)
            cleanup = False
            self.checks.verify_failed_work()

            self.evidence("evm-to-gno-timeout-refund.json", {
                "token": packet["token"], "amount": packet["amount"],
                "packet_hash": packet["packet_hash"],
                "timeout_timestamp_ns": packet["timeout_timestamp_ns"],
                "commitment_cleared": True, "gno_receive_count": 0,
                "transactions": {"mint": packet["mint_tx"], "approve": packet["approve_tx"],
                                 "send": packet["tx"], "pause_gno": recorded_pause_tx,
                                 "evm_timeout": log["transactionHash"], "unpause_gno": unpause_tx},
                "balance_deltas": deltas})
        finally:
            if cleanup:
                self.chain.pause_gno(False)

    def gno_to_evm_timeout_refund(self) -> None:
        plan = self.chain.wrapped_plan(self.state["channels"]["evm"])
        proxy = self.chain.proxy_address()
        before = self.chain.native_balance(proxy)
        cleanup = True

        try:
            pause_tx = self.chain.pause_evm(True)
            if not pause_tx:
                cleanup = False
                raise RuntimeError("EVM ZKGM was already paused")
            recorded_pause_tx = pause_tx

            sent = self.chain.send_raw(
                self.chain.encode_native_order(self.c["GNO_RECIPIENT"], plan, 0),
                TIMEOUT_REFUND_SECONDS)

            escrowed = self.chain.native_balance(proxy)
            if escrowed - before != 1:
                raise RuntimeError("Gno timeout send did not escrow one ugnot")

            timeout = self.chain.wait_events(["PacketTimeout"], {"packet_hash": sent["packet_hash"]}, 1)[0]
            if int(timeout["attrs"].get("timeout_timestamp", "0")) != sent["timeout_timestamp_ns"]:
                raise RuntimeError("Gno PacketTimeout timestamp does not match PacketSend")
            releases = [event for event in self.chain.gno_events(
                ["ZkgmNativeReleased"], realm=self.c["GNO_ZKGM_PORT"]) if event["tx"] == timeout["tx"]]
            if len(releases) != 1:
                raise RuntimeError("Gno timeout did not emit one native refund")
            refund = releases[0]["attrs"]
            if (refund.get("recipient") != self.c["GNO_RECIPIENT"] or
                    refund.get("denom") != "ugnot" or refund.get("amount") != "1"):
                raise RuntimeError("Gno timeout native refund does not match sender and amount")

            if self.chain.gno_events(["PacketAck"], {"packet_hash": sent["packet_hash"]}):
                raise RuntimeError("timed-out Gno packet was acknowledged")
            channel = self.chain.evm_channel_topic()
            if self.chain.evm_logs(self.c["EVM_IBC_HANDLER"], 0,
                             [PACKET_RECV_TOPIC, channel, sent["packet_hash"]]):
                raise RuntimeError("paused EVM unexpectedly received packet")
            if (not self.chain.gno_batch_commitment_cleared(sent["packet_hash"]) or
                    self.chain.native_balance(proxy) != before):
                raise RuntimeError("Gno timeout did not clear commitment and refund escrow")

            unpause_tx = self.chain.pause_evm(False)
            cleanup = False
            self.checks.verify_failed_work()

            self.evidence("gno-to-evm-timeout-refund.json", {
                "packet_hash": sent["packet_hash"], "source_tx": sent["tx"],
                "timeout_tx": timeout["tx"], "pause_tx": recorded_pause_tx, "unpause_tx": unpause_tx,
                "timeout_timestamp": sent["timeout_timestamp_ns"], "escrow_delta": 1,
                "refund_amount": "1"})
        finally:
            if cleanup:
                self.chain.pause_evm(False)

    def forged_proof_rejection(self) -> None:
        client = self.state["clients"]["gno_evm"]
        block = self.chain.block()

        target = self.v.wait(
            lambda: (height if int(height := self.v.latest_height(self.c["EVM_CHAIN_ID"], True)) >= block
                     else None), "finalized EVM height")
        self.v.call("msg", "update-client", self.c["GNO_CHAIN_ID"], str(client),
                    "--update-to", target, "-e")
        stored = self.v.wait(
            lambda: (height if int(str(height := self.v.client_height(
                self.c["GNO_CHAIN_ID"], client)).split("-")[-1]) >= int(target) else None),
            "Gno EVM client update")
        height = int(str(stored).split("-")[-1])

        channel = self.state["channels"]["evm"]
        commit = self.chain.channel_open_commitment(
            channel, self.state["connections"]["evm"], self.state["channels"]["gno"], VERSION)
        path_hex, value_hex, commitment = commit["path"], commit["value_hash"], commit["commitment"]
        path, value = bytes.fromhex(path_hex[2:]), bytes.fromhex(value_hex[2:])

        encoded = self.v.json(
            "rpc", "ibc-proof", self.c["EVM_CHAIN_ID"],
            json.dumps({"channel": {"channel_id": channel}}, separators=(",", ":")),
            "--height", str(stored), "--encode", "--ibc-interface", "ibc-gno",
            "--client-type", "state-lens/ics23/mpt")
        proof = bytes.fromhex(encoded.removeprefix("0x"))
        mutated = codec.mutate_proof(proof)

        proof_attrs = {"client_id": str(client), "proof_height": str(height), "path": path_hex}
        if self.chain.committed_proof(client, height, path) or self.chain.gno_events(
                ["CommitMembershipProof"], proof_attrs):
            raise RuntimeError("membership proof key was already committed")

        rejected = self.chain.submit_proof(client, height, mutated, path, value)
        self.evidence("forged-proof-mutated-gnokey.json", rejected)
        rejected_events = self.chain.gno_events(["CommitMembershipProof"], proof_attrs)
        if (rejected["accepted"] or self.chain.committed_proof(client, height, path) or
                rejected_events):
            raise RuntimeError("forged membership proof changed Gno state")

        control = self.chain.submit_proof(client, height, proof, path, value)
        self.evidence("forged-proof-valid-gnokey.json", control)
        if not control["accepted"]:
            raise RuntimeError("valid membership proof was rejected")
        event = self.chain.wait_events(["CommitMembershipProof"], proof_attrs, 1)[0]
        committed = self.chain.committed_proof(client, height, path)
        if committed.lower() != commitment.lower():
            raise RuntimeError("valid membership proof commitment does not match")

        self.evidence("forged-proof-rejection.json", {
            "name": "forged-proof-rejection", "client_id": client, "source_height": height,
            "path": path_hex, "expected_value_hash": commitment,
            "valid_proof_hash": "sha256:" + hashlib.sha256(proof).hexdigest(),
            "mutated_proof_hash": "sha256:" + hashlib.sha256(mutated).hexdigest(),
            "rejected_result": rejected, "rejected_event_count": len(rejected_events),
            "rejected_proof_committed": False, "valid_control_transaction": event["tx"],
            "valid_control_event_count": 1, "final_committed_value_hash": committed})
