from __future__ import annotations

import hashlib
import json
import os
import re
import stat
import subprocess
import sys
import tempfile
import time
import urllib.request
from pathlib import Path

from voyager import SCRIPT_DIR, VERSION, Voyager, command, operation, render_voyager


HASH = re.compile(r"^0x[0-9a-fA-F]{64}$")
ADDRESS = re.compile(r"^0x[0-9a-f]{40}$")
PACKET_SEND_TOPIC = "0x635b5d234fe7abddfb29b6c8498780a3175c9002c537f20a3d1bf9d0e625b5fe"
PACKET_ACK_TOPIC = "0x41d958a7d93b50b1f7541c6fc345d0c4657b1e83497baa562c866611ac1f69bb"
PACKET_TIMEOUT_TOPIC = "0x34df62ed9d26dbe71f13d2bd3f645d6cd16b0c44645ef783c2ed799748c80a74"
PACKET_RECV_TOPIC = "0xe450e03249d131499e278eeafd8e27effcceeb40b0b95628a087aa16b4b101d5"
WRITE_ACK_TOPIC = "0x488830ba53f27b7033e966a79427476ad47d550358e894bafeef8b97c6559251"
CREATE_TOKEN_TOPIC = "0x18469840730c2cbbd67b9f99f6421667b07f0169a795be80a28f182d602daf5b"
GNO_SENDER = "g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5"
GNO_MNEMONIC = ("source bonus chronic canvas draft south burst lottery vacant surface solve "
                "popular case indicate oppose farm nothing bullet exhibit title speed wink action roast")


class Runner:
    def __init__(self, config: dict, scenarios: list[str], resume: bool):
        self.c = config
        self.scenarios = scenarios
        self.resume = resume
        self.v = Voyager(config)
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

    def verify_failed_work(self, baseline: int | None = None) -> None:
        want = self.state["failed_work"]["final"] if baseline is None else baseline
        repaired = set(self.state["failed_work"]["repaired"])
        ids = [int(row["id"]) for row in self.v.failed_rows()]
        if want and not ids:
            raise RuntimeError("saved failed-work ID is ahead of Voyager queue")
        if want is not None and ids and want > max(ids):
            raise RuntimeError("saved failed-work ID is ahead of Voyager queue")
        got = max((item for item in ids if item not in repaired), default=0)
        if want is not None and got != want:
            raise RuntimeError(f"Voyager recorded new failed work: {got}, expected {want}")

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
            self.topology()
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
                methods[name]()
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
            self.verify_failed_work()
            return
        c = self.c
        baseline = self.v.failed_work()
        self.state["failed_work"]["baseline"] = baseline
        reserved = self.v.next_id(c["EVM_CHAIN_ID"], "client")
        self.v.restart(render_voyager(c, [reserved], [reserved + 1]))
        evm_from = self.v.latest_height(c["EVM_CHAIN_ID"], True)
        self.v.index(c["UNION_CHAIN_ID"])
        self.v.index(c["GNO_CHAIN_ID"])
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
        self.v.index(c["EVM_CHAIN_ID"], evm_from)
        next_evm = self.v.next_id(c["EVM_CHAIN_ID"], "client")
        plain, proof = [], []
        for item in range(1, next_evm):
            info = self.v.client_info(c["EVM_CHAIN_ID"], item)
            (proof if info["client_type"] == "proof-lens" else plain).append(item)
        self.state["allowlists"] = {
            "plain": ",".join(map(str, plain)), "proof_lens": ",".join(map(str, proof))}
        self.v.restart(render_voyager(c, plain, proof))
        self.verify_clients()
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
        gno_port = "0x" + c["GNO_ZKGM_PORT"].encode().hex()
        self.v.submit(operation(c["GNO_CHAIN_ID"], "channel_open_init", {
            "port_id": gno_port, "counterparty_port_id": c["EVM_ZKGM_CONTRACT"].lower(),
            "connection_id": connections["gno"], "version": VERSION}))
        self.wait_handshake("channel", channels)
        self.state["failed_work"]["final"] = baseline
        self.verify_failed_work(baseline)
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
                                 "0x" + self.c["GNO_ZKGM_PORT"].encode().hex())
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
        self.verify_clients()
        self.wait_handshake("connection", self.state["connections"])
        self.wait_handshake("channel", self.state["channels"])

    def verify_clients(self) -> None:
        clients = self.state["clients"]
        checks = (
            ("gno_union", self.c["GNO_CHAIN_ID"], self.c["UNION_CHAIN_ID"], "cometbls", "ibc-gno"),
            ("union_gno", self.c["UNION_CHAIN_ID"], self.c["GNO_CHAIN_ID"], "gno", "ibc-cosmwasm"),
            ("union_evm", self.c["UNION_CHAIN_ID"], self.c["EVM_CHAIN_ID"], "trusted/evm/mpt", "ibc-cosmwasm"),
            ("evm_union", self.c["EVM_CHAIN_ID"], self.c["UNION_CHAIN_ID"], "cometbls", "ibc-solidity"),
            ("gno_evm", self.c["GNO_CHAIN_ID"], self.c["EVM_CHAIN_ID"], "state-lens/ics23/mpt", "ibc-gno"),
            ("evm_gno", self.c["EVM_CHAIN_ID"], self.c["GNO_CHAIN_ID"], "proof-lens", "ibc-solidity"),
        )
        for name, chain, counterparty, client_type, interface in checks:
            client_id = clients[name]
            info = self.v.client_info(chain, client_id)
            meta = self.v.json("rpc", "client-meta", chain, str(client_id))
            query = json.dumps({"client_status": {"client_id": client_id}}, separators=(",", ":"))
            status = self.v.json("rpc", "query", chain, query)
            if (not info or info.get("client_type") != client_type or
                    info.get("ibc_interface") != interface or
                    meta.get("counterparty_chain_id") != counterparty or str(status).lower() != "active"):
                raise RuntimeError(f"client relation/status mismatch: {chain}/{client_id}")
        for side, name, l1, l2, l2_chain in (
            (self.c["GNO_CHAIN_ID"], "gno_evm", "gno_union", "union_evm", self.c["EVM_CHAIN_ID"]),
            (self.c["EVM_CHAIN_ID"], "evm_gno", "evm_union", "union_gno", self.c["GNO_CHAIN_ID"]),
        ):
            response = self.v.json("rpc", "client-state", side, str(clients[name]), "--decode")
            state = response.get("state", response)
            if isinstance(state, dict) and "@value" in state:
                state = state["@value"]
            if (int(state["l1_client_id"]) != clients[l1] or
                    int(state["l2_client_id"]) != clients[l2] or
                    state["l2_chain_id"] != l2_chain):
                raise RuntimeError(f"Lens client relation mismatch: {side}/{clients[name]}")

    # Packet operations stay as direct CLI/RPC calls.  There is deliberately no
    # client-interface layer: scenarios read like the transaction sequence.
    def cast(self, *args: str) -> str:
        return command(
            ["cast", *args], timeout=self.c["COMMAND_TIMEOUT"],
            env={"ETH_RPC_URL": self.c["EVM_PACKET_RPC_URL"]},
        )

    def receipt(self, label: str, *args: str) -> dict:
        try:
            value = json.loads(self.cast(*args))
        except json.JSONDecodeError as error:
            raise RuntimeError(f"malformed {label} receipt") from error
        if value.get("status") != "0x1" or not HASH.fullmatch(value.get("transactionHash", "")):
            raise RuntimeError(f"{label} transaction failed")
        return value

    def token_balance(self, token: str, owner: str) -> int:
        return int(self.cast("call", token.lower(), "balanceOf(address)(uint256)", owner).split()[0])

    def block(self) -> int:
        return int(self.cast("block-number"))

    def qeval(self, expression: str) -> str:
        return command([
            "gnokey", "query", "vm/qeval", "-remote", self.c["GNO_PACKET_RPC_URL"],
            "-data", expression,
        ], timeout=self.c["COMMAND_TIMEOUT"])

    def voucher_balance(self, voucher: str, owner: str) -> int:
        raw = self.qeval(f'{self.c["GNO_ZKGM_PORT"]}.VoucherBalanceOf("{voucher}",address("{owner}"))')
        match = re.search(r"\(([0-9]+)\s+int64\)", raw)
        if not match:
            raise RuntimeError("malformed Gno voucher balance")
        return int(match.group(1))

    def voucher_supply(self, registry_key: str) -> int:
        raw = self.qeval(f'gno.land/r/demo/defi/grc20reg.MustGet("{registry_key}").TotalSupply()')
        match = re.search(r"\(([0-9]+)\s+int64\)", raw)
        if not match:
            raise RuntimeError("malformed Gno voucher total supply")
        return int(match.group(1))

    def gno_events(self, event_types: list[str], attrs: dict[str, str] | None = None,
                   realm: str | None = None) -> list[dict]:
        attrs = attrs or {}
        realm = realm or self.c["GNO_IBC_CORE_REALM"]
        conditions = []
        for event_type in event_types:
            clauses = " ".join(
                f'{{ attrs: {{ key: {{ eq: {json.dumps(key)} }} value: {{ eq: {json.dumps(value)} }} }} }}'
                for key, value in attrs.items()
            )
            conditions.append(
                f'{{ GnoEvent: {{ type: {{ eq: {json.dumps(event_type)} }} '
                f'pkg_path: {{ eq: {json.dumps(realm)} }} _and: [{clauses}] }} }}'
            )
        query = (
            "{ getTransactions(where: { success: { eq: true } response: { events: { _or: [" +
            " ".join(conditions) +
            "] } } } order: { heightAndIndex: DESC }) { hash block_height response { events { "
            "... on GnoEvent { type pkg_path attrs { key value } } } } } }"
        )
        request = urllib.request.Request(
            self.c["GNO_PACKET_INDEXER_RPC_URL"],
            json.dumps({"query": query}).encode(), {"content-type": "application/json"},
        )
        try:
            with urllib.request.urlopen(request, timeout=self.c["COMMAND_TIMEOUT"]) as response:
                payload = json.load(response)
        except (OSError, json.JSONDecodeError) as error:
            raise RuntimeError("packet indexer request failed") from error
        if payload.get("errors"):
            raise RuntimeError("packet indexer returned errors")
        matches = []
        for tx in payload["data"]["getTransactions"]:
            for event in tx["response"]["events"]:
                pairs = {item["key"]: item["value"] for item in event.get("attrs", [])}
                if (event.get("pkg_path") == realm and event.get("type") in event_types and
                        all(pairs.get(key) == value for key, value in attrs.items())):
                    matches.append({"type": event["type"], "tx": tx["hash"],
                                    "height": int(tx["block_height"]), "attrs": pairs})
        return matches

    def wait_events(self, event_types: list[str], attrs: dict[str, str], count: int) -> list[dict]:
        def query():
            events = self.gno_events(event_types, attrs)
            if len(events) > count:
                raise RuntimeError(f"Gno event count={len(events)}, want {count}")
            return events if len(events) == count else None
        return self.v.wait(query, "Gno " + "/".join(event_types))

    @staticmethod
    def acknowledgement(attrs: dict[str, str]) -> str:
        if "acknowledgement" in attrs:
            return attrs["acknowledgement"]
        size = int(attrs["acknowledgement_size"])
        value = "".join(attrs[f"acknowledgement[{index}]"] for index in range(
            len([key for key in attrs if key.startswith("acknowledgement[")]))
        )
        if len(value) != size:
            raise RuntimeError("malformed Gno acknowledgement")
        return value

    @staticmethod
    def acknowledgement_success(value: str) -> bool:
        try:
            decoded = bytes.fromhex(value.removeprefix("0x"))
        except ValueError as error:
            raise RuntimeError("malformed acknowledgement") from error
        if (len(decoded) < 96 or len(decoded) % 32 or any(decoded[:31]) or
                any(decoded[32:63]) or decoded[63] != 64):
            raise RuntimeError("malformed acknowledgement")
        payload_length = int.from_bytes(decoded[64:96], "big")
        padded_length = (payload_length + 31) // 32 * 32
        if (len(decoded) != 96 + padded_length or
                any(decoded[96 + payload_length:]) or decoded[31] not in (0, 1)):
            raise RuntimeError("malformed acknowledgement")
        return decoded[31] == 1

    def evm_logs(self, address: str, from_block: int, topics: list) -> list[dict]:
        request = {"address": address, "fromBlock": hex(from_block), "toBlock": "latest",
                   "topics": topics}
        try:
            return json.loads(self.cast("rpc", "eth_getLogs", json.dumps(request, separators=(",", ":"))))
        except json.JSONDecodeError as error:
            raise RuntimeError("malformed EVM log response") from error

    def wait_evm_log(self, from_block: int, topics: list, label: str) -> dict:
        def query():
            logs = self.evm_logs(self.c["EVM_IBC_HANDLER"], from_block, topics)
            if len(logs) > 1:
                raise RuntimeError(f"{label} count={len(logs)}, want one")
            return logs[0] if logs else None
        return self.v.wait(query, label)

    def prepare_token(self, token: str, decimals: int, gno_channel: int) -> dict:
        token = token.lower()
        sender = self.cast("wallet", "address", "--private-key", self.c["EVM_PRIVATE_KEY"]).lower()
        if not ADDRESS.fullmatch(sender) or self.cast("code", token) == "0x":
            raise RuntimeError("invalid ERC20 fixture")
        if int(self.cast("call", token, "decimals()(uint8)").split()[0]) != decimals:
            raise RuntimeError(f"ERC20 must report {decimals} decimals")
        salt = "0x" + os.urandom(32).hex()
        tag = salt[2:]
        zero = "0x" + "0" * 40
        initializer = self.cast(
            "abi-encode", "f(address,address,string,string,uint8)", zero, zero,
            "Union E2E " + tag[:32], "UE" + tag[:6], str(decimals),
        )
        initializer = "0x8420ce99" + initializer.removeprefix("0x")
        metadata = self.cast("abi-encode", "f(bytes,bytes)", "0x6772633230", initializer)
        image = self.cast("keccak", metadata)
        encoded = self.cast("abi-encode", "f(uint256,uint32,bytes,uint256)",
                            "0", str(gno_channel), token, image)
        voucher = "ibc/" + self.cast("keccak", encoded)[2:42]
        return {"token": token, "sender": sender, "salt": salt, "tag": tag,
                "metadata": metadata, "voucher": voucher, "decimals": decimals}

    def send_token(self, plan: dict, recipient: str, amount: str, kind: int,
                   timeout_ns: int | None = None) -> dict:
        operand = self.cast(
            "abi-encode", "f(bytes,bytes,bytes,uint256,bytes,uint256,uint8,bytes)",
            plan["sender"], "0x" + recipient.encode().hex(), plan["token"], amount,
            "0x" + plan["voucher"].encode().hex(), amount, str(kind), plan["metadata"],
        )
        timeout_ns = timeout_ns or (time.time_ns() + 3_600_000_000_000)
        receipt = self.receipt(
            "packet", "send", self.c["EVM_ZKGM_CONTRACT"].lower(),
            "send(uint32,uint64,uint64,bytes32,(uint8,uint8,bytes))",
            str(self.state["channels"]["evm"]), "0", str(timeout_ns), plan["salt"],
            f"(2,3,{operand})", "--private-key", self.c["EVM_PRIVATE_KEY"], "--json",
        )
        logs = [item for item in receipt["logs"]
                if item.get("address", "").lower() == self.c["EVM_IBC_HANDLER"].lower()
                and item.get("topics", [""])[0].lower() == PACKET_SEND_TOPIC]
        if len(logs) != 1:
            raise RuntimeError("packet transaction did not emit exactly one PacketSend")
        # Packet hash is the third indexed event field in the pinned handler ABI.
        if logs[0]["topics"][1].lower() != f'0x{self.state["channels"]["evm"]:064x}':
            raise RuntimeError("PacketSend channel does not match")
        packet_hash = logs[0]["topics"][2]
        if not HASH.fullmatch(packet_hash):
            raise RuntimeError("malformed packet hash")
        return {"tx": receipt["transactionHash"], "packet_hash": packet_hash,
                "timeout_timestamp_ns": timeout_ns}

    def verify_evm_commitment_cleared(self, packet_hash: str) -> None:
        encoded = self.cast("abi-encode", "f(uint256,bytes32)", "4", packet_hash)
        key = self.cast("keccak", encoded)
        value = self.cast("call", self.c["EVM_IBC_HANDLER"].lower(),
                          "commitments(bytes32)(bytes32)", key).split()[0]
        if value.lower() != "0x02" + "0" * 62:
            raise RuntimeError("EVM packet commitment is still active")

    def submit_erc20(self, timeout_seconds: int = 0) -> dict:
        plan = self.prepare_token(self.c["EVM_TEST_ERC20"], 18, self.state["channels"]["gno"])
        amount = self.c["EVM_TEST_AMOUNT"]
        mint = self.receipt("mint", "send", plan["token"], "mint(address,uint256)",
                            plan["sender"], amount, "--private-key", self.c["EVM_PRIVATE_KEY"], "--json")
        approve = self.receipt("approve", "send", plan["token"], "approve(address,uint256)",
                              self.c["EVM_ZKGM_CONTRACT"].lower(), amount,
                              "--private-key", self.c["EVM_PRIVATE_KEY"], "--json")
        before = {"sender": self.token_balance(plan["token"], plan["sender"]),
                  "escrow": self.token_balance(plan["token"], self.c["EVM_ZKGM_CONTRACT"]),
                  "recipient": self.voucher_balance(plan["voucher"], self.c["GNO_RECIPIENT"])}
        from_block = self.block()
        timeout = time.time_ns() + timeout_seconds * 1_000_000_000 if timeout_seconds else None
        sent = self.send_token(plan, self.c["GNO_RECIPIENT"], amount, 0, timeout)
        return {**plan, **sent, "amount": amount, "recipient": self.c["GNO_RECIPIENT"],
                "mint_tx": mint["transactionHash"], "approve_tx": approve["transactionHash"],
                "before": before, "from_block": from_block,
                "failed_work_baseline": self.state["failed_work"]["final"]}

    def observe_erc20(self, packet: dict, want_success: bool = True) -> dict:
        events = self.wait_events(["PacketRecv", "WriteAck"],
                                  {"packet_hash": packet["packet_hash"]}, 2)
        recv = [item for item in events if item["type"] == "PacketRecv"]
        write = [item for item in events if item["type"] == "WriteAck"]
        if len(recv) != 1 or len(write) != 1 or recv[0]["tx"] != write[0]["tx"]:
            raise RuntimeError("Gno PacketRecv and WriteAck do not form one transaction")
        log = self.wait_evm_log(
            packet["from_block"], [PACKET_ACK_TOPIC, f'0x{self.state["channels"]["evm"]:064x}',
                                   packet["packet_hash"]], "EVM PacketAck")
        decoded = json.loads(self.cast("decode-abi", "f()(bytes)", log["data"], "--json"))[0]
        source_ack = self.acknowledgement(write[0]["attrs"])
        if source_ack.lower().removeprefix("0x") != decoded.lower().removeprefix("0x"):
            raise RuntimeError("cross-chain acknowledgement bytes differ")
        # ZKGM Ack is successful when the first ABI tag is 1.
        success = self.acknowledgement_success(source_ack)
        if success != want_success:
            raise RuntimeError(f"acknowledgement success={success}, want {want_success}")
        self.verify_evm_commitment_cleared(packet["packet_hash"])
        after = {"sender": self.token_balance(packet["token"], packet["sender"]),
                 "escrow": self.token_balance(packet["token"], self.c["EVM_ZKGM_CONTRACT"]),
                 "recipient": self.voucher_balance(packet["voucher"], packet["recipient"])}
        deltas = {key: after[key] - packet["before"][key] for key in after}
        expected = int(packet["amount"])
        expected_deltas = ({"sender": -expected, "escrow": expected,
                            "recipient": expected // 10 ** max(int(packet["decimals"]) - 6, 0)} if success else
                           {"sender": 0, "escrow": 0, "recipient": 0})
        if deltas != expected_deltas:
            raise RuntimeError(f"unexpected packet balance deltas: {deltas}")
        self.verify_failed_work(packet["failed_work_baseline"])
        return {"outcome": "success" if success else "failure", "token": packet["token"],
                "packet_hash": packet["packet_hash"], "commitment_cleared": True,
                "transactions": {"mint": packet["mint_tx"], "approve": packet["approve_tx"],
                                 "send": packet["tx"], "gno_receive": recv[0]["tx"],
                                 "gno_write_ack": write[0]["tx"],
                                 "evm_ack": log["transactionHash"]},
                "balance_deltas": deltas}

    def erc20_to_gno(self) -> None:
        if self.packet:
            raise RuntimeError("ERC20 packet already submitted")
        self.packet = self.submit_erc20()
        result = self.observe_erc20(self.packet)
        self.packet["outcome"] = result["outcome"]
        self.evidence("packet-summary.json", result)

    def deploy_token(self, name: str, symbol: str, decimals: int) -> str:
        with tempfile.TemporaryDirectory(prefix="union-erc20-") as output:
            raw = command([
                "forge", "create", "--root", str(SCRIPT_DIR), "--out", output, "--no-cache",
                "--rpc-url", self.c["EVM_PACKET_RPC_URL"], "--private-key", self.c["EVM_PRIVATE_KEY"],
                "--broadcast", "--json", "fixtures/TestERC20.sol:TestERC20",
                "--constructor-args", name, symbol, str(decimals),
            ], timeout=self.c["TIMEOUT"])
        token = json.loads(raw)["deployedTo"].lower()
        if not ADDRESS.fullmatch(token):
            raise RuntimeError("malformed ERC20 deployment response")
        return token

    def boundary_order(self, name: str, plan: dict, amount: str, kind: int,
                       want_success: bool) -> dict:
        mint = self.receipt("mint", "send", plan["token"], "mint(address,uint256)",
                            plan["sender"], amount, "--private-key", self.c["EVM_PRIVATE_KEY"], "--json")
        approve = self.receipt("approve", "send", plan["token"], "approve(address,uint256)",
                              self.c["EVM_ZKGM_CONTRACT"], amount,
                              "--private-key", self.c["EVM_PRIVATE_KEY"], "--json")
        before = {"sender": self.token_balance(plan["token"], plan["sender"]),
                  "escrow": self.token_balance(plan["token"], self.c["EVM_ZKGM_CONTRACT"]),
                  "recipient": self.voucher_balance(plan["voucher"], self.c["GNO_RECIPIENT"])}
        from_block = self.block()
        packet = {**plan, **self.send_token(plan, self.c["GNO_RECIPIENT"], amount, kind),
                  "amount": amount, "recipient": self.c["GNO_RECIPIENT"], "before": before,
                  "from_block": from_block, "mint_tx": mint["transactionHash"],
                  "approve_tx": approve["transactionHash"],
                  "failed_work_baseline": self.state["failed_work"]["final"]}
        result = self.observe_erc20(packet, want_success)
        return {"name": name, **result}

    def amount_boundaries(self) -> None:
        if not self.packet or self.packet.get("outcome") != "success":
            raise RuntimeError("amount boundaries require a successful ERC20 packet")
        overflow = self.deploy_token("Union Overflow", "UOF", 6)
        overflow_plan = self.prepare_token(overflow, 6, self.state["channels"]["gno"])
        first = self.boundary_order("max-plus-one-refund", overflow_plan,
                                    "9223372036854775808", 0, False)
        cumulative = self.deploy_token("Union Cumulative", "UCM", 6)
        cumulative_plan = self.prepare_token(cumulative, 6, self.state["channels"]["gno"])
        second = self.boundary_order("max-succeeds", cumulative_plan,
                                     "9223372036854775807", 0, True)
        cumulative_plan["salt"] = "0x" + os.urandom(32).hex()
        third = self.boundary_order("cumulative-overflow-refund", cumulative_plan, "1", 1, False)
        if self.voucher_balance(cumulative_plan["voucher"], self.c["GNO_RECIPIENT"]) != 9223372036854775807:
            raise RuntimeError("cumulative overflow changed maximum voucher balance")
        registry_key = self.c["GNO_ZKGM_PORT"] + ".UE" + cumulative_plan["tag"][:6]
        supply = self.voucher_supply(registry_key)
        if supply != 9223372036854775807:
            raise RuntimeError("cumulative overflow changed maximum voucher supply")
        third["voucher_supply"] = str(supply)
        self.evidence("amount-boundaries.json", [first, second, third])

    def native_balance(self, owner: str, denom: str = "ugnot") -> int:
        raw = command(["gnokey", "query", "bank/balances/" + owner,
                       "-remote", self.c["GNO_PACKET_RPC_URL"]],
                      timeout=self.c["COMMAND_TIMEOUT"])
        match = re.search(r'data: "([^"]*)"', raw)
        if not match:
            raise RuntimeError("malformed Gno native balance")
        for coin in match.group(1).split(","):
            found = re.fullmatch(r"([0-9]+)(.+)", coin.strip())
            if found and found.group(2) == denom:
                return int(found.group(1))
        return 0

    def proxy_address(self) -> str:
        raw = self.qeval(self.c["GNO_ZKGM_PORT"] + ".ProxyAddress()")
        match = re.search(r'"(g1[0-9a-z]{38})"', raw)
        if not match:
            raise RuntimeError("malformed Gno proxy address")
        return match.group(1)

    def wrapped_plan(self, evm_channel: int, base: str = "ugnot") -> dict:
        sender = self.cast("wallet", "address", "--private-key", self.c["EVM_PRIVATE_KEY"]).lower()
        fao = self.cast("call", self.c["EVM_ZKGM_CONTRACT"], "FAO_IMPL()(address)").split()[0].lower()
        implementation = self.cast("call", fao, "ERC20_IMPL()(address)").split()[0].lower()
        tag = os.urandom(32).hex()
        initializer = self.cast(
            "abi-encode", "f(address,address,string,string,uint8)", sender,
            self.c["EVM_ZKGM_CONTRACT"].lower(), "Union Gno " + tag[:32], "UG" + tag[:6], "6")
        initializer = "0x8420ce99" + initializer.removeprefix("0x")
        metadata = self.cast("abi-encode", "f(bytes,bytes)", implementation, initializer)
        fields = json.loads(self.cast("decode-abi", "f()(bytes,bytes)", metadata, "--json"))
        predicted = self.cast(
            "call", self.c["EVM_ZKGM_CONTRACT"],
            "predictWrappedTokenV2(uint256,uint32,bytes,(bytes,bytes))(address,bytes32)",
            "0", str(evm_channel), "0x" + base.encode().hex(), f"({fields[0]},{fields[1]})",
        ).split()[0].lower()
        if not ADDRESS.fullmatch(predicted):
            raise RuntimeError("malformed wrapped token prediction")
        return {"token": predicted, "sender": sender, "metadata": metadata}

    def encode_native_order(self, wire_sender: str, plan: dict, kind: int) -> str:
        return self.cast(
            "abi-encode", "f(bytes,bytes,bytes,uint256,bytes,uint256,uint8,bytes)",
            "0x" + wire_sender.encode().hex(), plan["sender"], "0x" + b"ugnot".hex(), "1",
            plan["token"], "1", str(kind), plan["metadata"],
        )

    def gno_home(self) -> tempfile.TemporaryDirectory:
        directory = tempfile.TemporaryDirectory(prefix="union-gnokey-")
        command(["gnokey", "add", "-recover", "-insecure-password-stdin", "-home",
                 directory.name, "sender"], timeout=self.c["COMMAND_TIMEOUT"],
                stdin=GNO_MNEMONIC + "\n\n\n")
        listed = command(["gnokey", "list", "-home", directory.name],
                         timeout=self.c["COMMAND_TIMEOUT"])
        if GNO_SENDER not in listed:
            directory.cleanup()
            raise RuntimeError("Gno dev sender fixture address is incorrect")
        return directory

    def send_raw(self, operand: str, timeout_seconds: int = 3600) -> dict:
        channel = self.state["channels"]["gno"]
        existing = self.gno_events(["PacketSend"], {"source_channel_id": str(channel)})
        before = max((event["height"] for event in existing), default=0)
        timeout_ns = time.time_ns() + timeout_seconds * 1_000_000_000
        salt = os.urandom(32).hex()
        home = self.gno_home()
        try:
            args = ["gnokey", "maketx", "call", "-pkgpath", self.c["GNO_ZKGM_PORT"],
                    "-func", "SendRaw", "-gas-fee", "5000000ugnot", "-gas-wanted", "200000000",
                    "-broadcast", "-chainid", self.c["GNO_CHAIN_ID"], "-remote",
                    self.c["GNO_PACKET_RPC_URL"], "-insecure-password-stdin", "-home", home.name,
                    "-send", "1ugnot"]
            for value in (str(channel), str(timeout_ns), salt, "2", "3", operand):
                args += ["-args", value]
            args.append("sender")
            command(args, timeout=self.c["COMMAND_TIMEOUT"], stdin="\n")
        finally:
            home.cleanup()
        def query():
            candidates = [event for event in self.gno_events(
                ["PacketSend"], {"source_channel_id": str(channel)}) if event["height"] > before]
            if len(candidates) > 1:
                raise RuntimeError("multiple new Gno PacketSend events")
            return candidates[0] if candidates else None
        event = self.v.wait(query, "Gno PacketSend")
        packet_hash = event["attrs"].get("packet_hash", "")
        if not HASH.fullmatch(packet_hash):
            raise RuntimeError("malformed Gno packet hash")
        return {"tx": event["tx"], "packet_hash": packet_hash, "height": event["height"],
                "timeout_timestamp_ns": timeout_ns}

    def wait_evm_receive(self, from_block: int, packet_hash: str) -> dict:
        channel = f'0x{self.state["channels"]["evm"]:064x}'
        def query():
            logs = self.evm_logs(self.c["EVM_IBC_HANDLER"], from_block,
                                 [[PACKET_RECV_TOPIC, WRITE_ACK_TOPIC], channel, packet_hash])
            receives = [log for log in logs if log["topics"][0].lower() == PACKET_RECV_TOPIC]
            writes = [log for log in logs if log["topics"][0].lower() == WRITE_ACK_TOPIC]
            if len(receives) > 1 or len(writes) > 1:
                raise RuntimeError("multiple EVM receive/write acknowledgement logs")
            if not receives or not writes:
                return None
            if receives[0]["transactionHash"] != writes[0]["transactionHash"]:
                raise RuntimeError("EVM PacketRecv and WriteAck transactions differ")
            ack = json.loads(self.cast("decode-abi", "f()(bytes)", writes[0]["data"], "--json"))[0]
            return {"tx": receives[0]["transactionHash"], "acknowledgement": ack}
        return self.v.wait(query, "EVM PacketRecv/WriteAck")

    def wait_gno_ack(self, packet_hash: str) -> dict:
        event = self.wait_events(["PacketAck"], {"packet_hash": packet_hash}, 1)[0]
        return {"tx": event["tx"], "acknowledgement": self.acknowledgement(event["attrs"])}

    def union_membership_height(self, client_id: int, minimum: int, path: str) -> int:
        body = json.dumps({
            "jsonrpc": "2.0", "id": 1, "method": "tx_search",
            "params": {"query": f"wasm-commit_membership_proof.client_id='{client_id}'",
                       "prove": False, "page": "1", "per_page": "100", "order_by": "desc"},
        }).encode()
        request = urllib.request.Request(self.c["UNION_PACKET_RPC_URL"], body,
                                         {"content-type": "application/json"})
        try:
            with urllib.request.urlopen(request, timeout=self.c["COMMAND_TIMEOUT"]) as response:
                payload = json.load(response)
        except (OSError, json.JSONDecodeError) as error:
            raise RuntimeError("Union membership search failed") from error
        matches = []
        expected_path = path.lower().removeprefix("0x")
        for tx in payload.get("result", {}).get("txs", []):
            for event in tx["tx_result"]["events"]:
                if event["type"] not in ("wasm-commit_membership_proof", "commit_membership_proof"):
                    continue
                attrs = {item["key"]: item["value"] for item in event["attributes"]}
                height = int(attrs.get("proof_height", 0))
                if (attrs.get("client_id") == str(client_id) and height >= minimum and
                        attrs.get("path", "").lower().removeprefix("0x") == expected_path):
                    matches.append(height)
        if not matches:
            raise RuntimeError("Union membership proof coverage was not found")
        return min(matches)

    def gno_order(self, name: str, wire_sender: str, plan: dict, kind: int,
                  want_success: bool) -> dict:
        from_block = self.block()
        sent = self.send_raw(self.encode_native_order(wire_sender, plan, kind))
        receive = self.wait_evm_receive(from_block, sent["packet_hash"])
        encoded_path = self.cast("abi-encode", "f(uint256,bytes32)", "4", sent["packet_hash"])
        membership_path = self.cast("keccak", encoded_path)
        membership_height = self.union_membership_height(
            self.state["clients"]["union_gno"], sent["height"] + 1, membership_path)
        proof_height = self.v.client_height(
            self.c["EVM_CHAIN_ID"], self.state["clients"]["evm_gno"])
        if int(str(proof_height).split("-")[-1]) < membership_height:
            raise RuntimeError("EVM Proof Lens height does not cover Union membership proof")
        ack = self.wait_gno_ack(sent["packet_hash"])
        if (ack["acknowledgement"].lower().removeprefix("0x") !=
                receive["acknowledgement"].lower().removeprefix("0x")):
            raise RuntimeError("Gno/EVM acknowledgement bytes differ")
        success = self.acknowledgement_success(ack["acknowledgement"])
        if success != want_success:
            raise RuntimeError(f"{name} acknowledgement success={success}, want {want_success}")
        raw = self.qeval(
            'gno.land/r/onbloc/ibc/union/testing/e2e_setup.QueryBatchPacketCommitment("' +
            sent["packet_hash"].removeprefix("0x") + '")')
        if "0x02" + "00" * 31 not in raw:
            raise RuntimeError("Gno packet commitment is still active")
        self.verify_failed_work()
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
        plan = self.wrapped_plan(self.state["channels"]["evm"])
        lifecycle_from = self.block()
        proxy = self.proxy_address()
        before = self.native_balance(proxy)
        initialize = self.gno_order("initialize", self.c["GNO_RECIPIENT"], plan, 0, True)
        escrow = self.gno_order("escrow", self.c["GNO_RECIPIENT"], plan, 1, True)
        if self.native_balance(proxy) - before != 2:
            raise RuntimeError("Gno proxy did not escrow both lifecycle sends")
        if self.cast("code", plan["token"]) == "0x":
            raise RuntimeError("EVM wrapped token was not deployed")
        balance = self.token_balance(plan["token"], plan["sender"])
        supply = int(self.cast("call", plan["token"], "totalSupply()(uint256)").split()[0])
        if balance != 2 or supply != 2:
            raise RuntimeError("wrapped token initialize/escrow state is incorrect")
        creation_logs = self.evm_logs(
            self.c["EVM_ZKGM_CONTRACT"], lifecycle_from,
            [CREATE_TOKEN_TOPIC, f'0x{self.state["channels"]["evm"]:064x}',
             "0x" + "0" * 24 + plan["token"].removeprefix("0x")])
        if len(creation_logs) != 1:
            raise RuntimeError("wrapped token creation event count is not one")

        self.receipt("approve wrapped token", "send", plan["token"],
                     "approve(address,uint256)", self.c["EVM_ZKGM_CONTRACT"], "1",
                     "--private-key", self.c["EVM_PRIVATE_KEY"], "--json")
        receiver = "g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm"
        receiver_before = self.native_balance(receiver)
        proxy_before = self.native_balance(proxy)
        from_block = self.block()
        return_plan = {"token": plan["token"], "sender": plan["sender"], "voucher": "ugnot",
                       "metadata": "0x", "salt": "0x" + os.urandom(32).hex(), "decimals": 6}
        sent = self.send_token(return_plan, receiver, "1", 2)
        events = self.wait_events(["PacketRecv", "WriteAck"],
                                  {"packet_hash": sent["packet_hash"]}, 2)
        write = next(event for event in events if event["type"] == "WriteAck")
        ack_log = self.wait_evm_log(from_block, [PACKET_ACK_TOPIC,
            f'0x{self.state["channels"]["evm"]:064x}', sent["packet_hash"]], "EVM PacketAck")
        evm_ack = json.loads(self.cast("decode-abi", "f()(bytes)", ack_log["data"], "--json"))[0]
        if (self.acknowledgement(write["attrs"]).lower().removeprefix("0x") !=
                evm_ack.lower().removeprefix("0x")) or not self.acknowledgement_success(evm_ack):
            raise RuntimeError("UNESCROW did not receive a success acknowledgement")
        self.verify_evm_commitment_cleared(sent["packet_hash"])
        if (self.token_balance(plan["token"], plan["sender"]) != 1 or
                int(self.cast("call", plan["token"], "totalSupply()(uint256)").split()[0]) != 1 or
                self.native_balance(receiver) - receiver_before != 1 or
                self.native_balance(proxy) - proxy_before != -1):
            raise RuntimeError("UNESCROW lifecycle balances are incorrect")
        unescrow = {"name": "unescrow", "packet_hash": sent["packet_hash"],
                    "source_tx": sent["tx"], "destination_tx": write["tx"],
                    "ack_tx": ack_log["transactionHash"], "success": True}
        invalid_plan = self.wrapped_plan(self.state["channels"]["evm"] + 1)
        invalid_proxy_before = self.native_balance(proxy)
        invalid_receiver_before = self.native_balance(receiver)
        invalid = self.gno_order(
            "invalid-quote-refund", receiver, invalid_plan, 0, False)
        if (self.native_balance(proxy) != invalid_proxy_before or
                self.native_balance(receiver) - invalid_receiver_before != 1):
            raise RuntimeError("invalid quote packet was not fully refunded")
        if self.gno_events(["PacketTimeout"], {"packet_hash": invalid["packet_hash"]}):
            raise RuntimeError("invalid quote packet unexpectedly timed out")
        self.evidence("gno-to-evm.json", {"lifecycle": [initialize, escrow, unescrow],
                                         "invalid_quote": invalid})

    def allowlists(self) -> tuple[list[int], list[int]]:
        return ([int(item) for item in self.state["allowlists"]["plain"].split(",") if item],
                [int(item) for item in self.state["allowlists"]["proof_lens"].split(",") if item])

    def relayer_address(self, private_key: str) -> str:
        address = self.cast("wallet", "address", "--private-key", private_key).lower()
        if int(self.cast("balance", address)) != 0:
            raise RuntimeError("relayer fixture must start with zero EVM balance")
        return address

    def restart_with_key(self, private_key: str) -> None:
        plain, proof = self.allowlists()
        config = dict(self.c)
        config["EVM_PRIVATE_KEY"] = private_key
        self.v.restart(render_voyager(config, plain, proof))

    def secondary(self) -> Voyager:
        plain, proof = self.allowlists()
        runtime = Voyager(self.c)
        runtime.start(render_voyager(self.c, plain, proof))
        return runtime

    def tx_sender(self, tx_hash: str) -> str:
        return json.loads(self.cast("tx", tx_hash, "--json"))["from"].lower()

    def relayer_insufficient_balance_failover(self) -> None:
        key = self.c["RELAYER_EMPTY_PRIVATE_KEY"]
        primary = self.relayer_address(key)
        self.restart_with_key(key)
        secondary = None
        try:
            packet = self.submit_erc20()
            self.wait_events(["PacketRecv", "WriteAck"],
                             {"packet_hash": packet["packet_hash"]}, 2)
            stats = self.v.wait(lambda: (value if int((value := self.v.active_queue())["total"]) > 0
                                         else None), "active relayer queue")
            secondary = self.secondary()
            result = self.observe_erc20(packet)
            ack_tx = result["transactions"]["evm_ack"]
            signer = self.tx_sender(ack_tx)
            expected = self.cast("wallet", "address", "--private-key", self.c["EVM_PRIVATE_KEY"]).lower()
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
        primary = self.relayer_address(key)
        self.restart_with_key(key)
        plain, proof = self.allowlists()
        self.v.close()
        packet = self.submit_erc20()
        secondary = Voyager(self.c)
        try:
            secondary.start(render_voyager(self.c, plain, proof))
            # All direct observations are chain RPC reads; the secondary shares the queue DB.
            original = self.v
            self.v = secondary
            try:
                result = self.observe_erc20(packet)
            finally:
                self.v = original
            signer = self.tx_sender(result["transactions"]["evm_ack"])
            expected = self.cast("wallet", "address", "--private-key", self.c["EVM_PRIVATE_KEY"]).lower()
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
        address = self.relayer_address(key)
        self.restart_with_key(key)
        try:
            packet = self.submit_erc20()
            self.wait_events(["PacketRecv", "WriteAck"], {"packet_hash": packet["packet_hash"]}, 2)
            channel = f'0x{self.state["channels"]["evm"]:064x}'
            pending_until = time.monotonic() + 2 * self.c["EVM_REFRESH"]
            while time.monotonic() < pending_until:
                if self.evm_logs(self.c["EVM_IBC_HANDLER"], packet["from_block"],
                                 [PACKET_ACK_TOPIC, channel, packet["packet_hash"]]):
                    raise RuntimeError("zero-balance relayer unexpectedly acknowledged packet")
                time.sleep(self.c["POLL"])
            stats = self.v.wait(lambda: (value if int((value := self.v.active_queue())["total"]) > 0
                                         else None), "active relayer queue")
            fund = self.receipt("fund relayer", "send", address, "--value", "1000000000000000000",
                                "--private-key", self.c["EVM_PRIVATE_KEY"], "--json")
            result = self.observe_erc20(packet)
            if self.tx_sender(result["transactions"]["evm_ack"]) != address:
                raise RuntimeError("recovered relayer did not sign EVM acknowledgement")
            balance = int(self.cast("balance", address))
            if balance <= 0:
                raise RuntimeError("funded relayer has no remaining balance")
            self.evidence("relayer-balance-recovery.json", {
                "primary_signer": address, "balance_before_wei": "0",
                "balance_after_wei": str(balance), "active_queue_before_funding": stats,
                "packet_hash": packet["packet_hash"], "active_retry_completed": True,
                "transactions": {**result["transactions"], "fund": fund["transactionHash"]}})
        finally:
            self.restart_with_key(self.c["EVM_PRIVATE_KEY"])

    def pause_gno(self, paused: bool) -> str:
        event_type = "ZkgmPaused" if paused else "ZkgmUnpaused"
        existing = self.gno_events([event_type], realm=self.c["GNO_ZKGM_PORT"])
        before = max((event["height"] for event in existing), default=0)
        home = self.gno_home()
        try:
            command([
                "gnokey", "maketx", "call", "-pkgpath", self.c["GNO_ZKGM_PORT"],
                "-func", "Pausable", "-gas-fee", "1000000ugnot", "-gas-wanted", "90000000",
                "-broadcast", "-chainid", self.c["GNO_CHAIN_ID"], "-remote",
                self.c["GNO_PACKET_RPC_URL"], "-insecure-password-stdin", "-home", home.name,
                "-args", str(paused).lower(), "sender",
            ], timeout=self.c["COMMAND_TIMEOUT"], stdin="\n")
        finally:
            home.cleanup()
        def query():
            found = [event for event in self.gno_events(
                [event_type], realm=self.c["GNO_ZKGM_PORT"]) if event["height"] > before]
            return found[0]["tx"] if len(found) == 1 else None
        return self.v.wait(query, "Gno " + event_type)

    def pause_evm(self, paused: bool) -> str:
        current = self.cast("call", self.c["EVM_ZKGM_CONTRACT"], "paused()(bool)").lower() == "true"
        if current == paused:
            return ""
        method = "pause()" if paused else "unpause()"
        return self.receipt(
            "ZKGM pause", "send", self.c["EVM_ZKGM_CONTRACT"], method,
            "--private-key", self.c["EVM_PRIVATE_KEY"], "--json")["transactionHash"]

    def evm_to_gno_timeout_refund(self) -> None:
        cleanup = True
        try:
            pause_tx = self.pause_gno(True)
            recorded_pause_tx = pause_tx
            packet = self.submit_erc20(180)
            channel = f'0x{self.state["channels"]["evm"]:064x}'
            def timeout_query():
                logs = self.evm_logs(
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
            self.verify_evm_commitment_cleared(packet["packet_hash"])
            if self.gno_events(["PacketRecv"], {"packet_hash": packet["packet_hash"]}):
                raise RuntimeError("paused Gno unexpectedly received packet")
            after = {"sender": self.token_balance(packet["token"], packet["sender"]),
                     "escrow": self.token_balance(packet["token"], self.c["EVM_ZKGM_CONTRACT"]),
                     "recipient": self.voucher_balance(packet["voucher"], packet["recipient"])}
            deltas = {key: after[key] - packet["before"][key] for key in after}
            if deltas != {"sender": 0, "escrow": 0, "recipient": 0}:
                raise RuntimeError("EVM timeout did not fully refund balances")
            unpause_tx = self.pause_gno(False)
            cleanup = False
            self.verify_failed_work()
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
                self.pause_gno(False)

    def gno_to_evm_timeout_refund(self) -> None:
        plan = self.wrapped_plan(self.state["channels"]["evm"])
        proxy = self.proxy_address()
        before = self.native_balance(proxy)
        cleanup = True
        try:
            pause_tx = self.pause_evm(True)
            if not pause_tx:
                cleanup = False
                raise RuntimeError("EVM ZKGM was already paused")
            recorded_pause_tx = pause_tx
            sent = self.send_raw(self.encode_native_order(self.c["GNO_RECIPIENT"], plan, 0), 180)
            escrowed = self.native_balance(proxy)
            if escrowed - before != 1:
                raise RuntimeError("Gno timeout send did not escrow one ugnot")
            timeout = self.wait_events(["PacketTimeout"], {"packet_hash": sent["packet_hash"]}, 1)[0]
            if int(timeout["attrs"].get("timeout_timestamp", "0")) != sent["timeout_timestamp_ns"]:
                raise RuntimeError("Gno PacketTimeout timestamp does not match PacketSend")
            releases = [event for event in self.gno_events(
                ["ZkgmNativeReleased"], realm=self.c["GNO_ZKGM_PORT"]) if event["tx"] == timeout["tx"]]
            if len(releases) != 1:
                raise RuntimeError("Gno timeout did not emit one native refund")
            refund = releases[0]["attrs"]
            if (refund.get("recipient") != self.c["GNO_RECIPIENT"] or
                    refund.get("denom") != "ugnot" or refund.get("amount") != "1"):
                raise RuntimeError("Gno timeout native refund does not match sender and amount")
            if self.gno_events(["PacketAck"], {"packet_hash": sent["packet_hash"]}):
                raise RuntimeError("timed-out Gno packet was acknowledged")
            channel = f'0x{self.state["channels"]["evm"]:064x}'
            if self.evm_logs(self.c["EVM_IBC_HANDLER"], 0,
                             [PACKET_RECV_TOPIC, channel, sent["packet_hash"]]):
                raise RuntimeError("paused EVM unexpectedly received packet")
            raw = self.qeval(
                'gno.land/r/onbloc/ibc/union/testing/e2e_setup.QueryBatchPacketCommitment("' +
                sent["packet_hash"].removeprefix("0x") + '")')
            if "0x02" + "00" * 31 not in raw or self.native_balance(proxy) != before:
                raise RuntimeError("Gno timeout did not clear commitment and refund escrow")
            unpause_tx = self.pause_evm(False)
            cleanup = False
            self.verify_failed_work()
            self.evidence("gno-to-evm-timeout-refund.json", {
                "packet_hash": sent["packet_hash"], "source_tx": sent["tx"],
                "timeout_tx": timeout["tx"], "pause_tx": recorded_pause_tx, "unpause_tx": unpause_tx,
                "timeout_timestamp": sent["timeout_timestamp_ns"], "escrow_delta": 1,
                "refund_amount": "1"})
        finally:
            if cleanup:
                self.pause_evm(False)

    def committed_proof(self, client: int, height: int, path: bytes) -> str:
        raw = self.qeval(
            "gno.land/r/onbloc/ibc/union/testing/e2e_setup.QueryCommittedMembershipProof"
            f'({client},{height},"{path.hex()}")')
        match = re.search(r'"(0x[0-9a-f]{64})"', raw)
        if match:
            return match.group(1)
        if '("" string)' in raw:
            return ""
        raise RuntimeError("malformed committed membership proof response")

    @staticmethod
    def mutate_proof(proof: bytes) -> bytes:
        mutated = bytearray(proof)
        if len(mutated) < 72:
            raise RuntimeError("malformed encoded storage proof")
        count = int.from_bytes(mutated[64:72], "little")
        offset = 72
        for _ in range(count):
            if offset + 8 > len(mutated):
                break
            size = int.from_bytes(mutated[offset:offset + 8], "little")
            offset += 8
            if size and offset + size <= len(mutated):
                mutated[offset + size - 1] ^= 1
                return bytes(mutated)
            offset += size
        raise RuntimeError("encoded storage proof has no MPT node")

    def submit_proof(self, client: int, height: int, proof: bytes,
                     path: bytes, value: bytes) -> dict:
        args = ["go", "run", "proof_submit.go", self.c["GNO_IBC_CORE_REALM"],
                str(client), str(height), proof.hex(),
                path.hex(), value.hex(), self.c["GNO_CHAIN_ID"], self.c["GNO_PACKET_RPC_URL"]]
        result = subprocess.run(args, cwd=SCRIPT_DIR, text=True, capture_output=True,
                                timeout=self.c["COMMAND_TIMEOUT"], check=False,
                                env={**os.environ, "GOWORK": "off"},
                                input=self.c["GNO_PRIVATE_KEY"] + "\n")
        output = (result.stdout + "\n" + result.stderr).lower()
        if result.returncode == 0:
            return {"accepted": True, "classification": "accepted", "stdout": result.stdout}
        if any(word in output for word in ("proof", "mpt", "root", "hash mismatch", "invalid node")):
            return {"accepted": False, "classification": "proof verification rejected",
                    "stdout": result.stdout, "stderr": result.stderr}
        raise RuntimeError("Gno proof transaction failed unexpectedly: " + result.stderr[-1000:])

    def forged_proof_rejection(self) -> None:
        client = self.state["clients"]["gno_evm"]
        block = self.block()
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
        encoded_path = self.cast("abi-encode", "f(uint256,uint256)", "3", str(channel))
        path_hex = self.cast("keccak", encoded_path)
        tuple_value = (f'(3,{self.state["connections"]["evm"]},'
                       f'{self.state["channels"]["gno"]},0x{self.c["GNO_ZKGM_PORT"].encode().hex()},'
                       f'{VERSION})')
        encoded_value = self.cast("abi-encode", "f((uint8,uint32,uint32,bytes,string))", tuple_value)
        value_hex = self.cast("keccak", encoded_value)
        commitment = self.cast("keccak", value_hex)
        path, value = bytes.fromhex(path_hex[2:]), bytes.fromhex(value_hex[2:])
        encoded = self.v.json(
            "rpc", "ibc-proof", self.c["EVM_CHAIN_ID"],
            json.dumps({"channel": {"channel_id": channel}}, separators=(",", ":")),
            "--height", str(stored), "--encode", "--ibc-interface", "ibc-gno",
            "--client-type", "state-lens/ics23/mpt")
        proof = bytes.fromhex(encoded.removeprefix("0x"))
        mutated = self.mutate_proof(proof)
        proof_attrs = {"client_id": str(client), "proof_height": str(height), "path": path_hex}
        if self.committed_proof(client, height, path) or self.gno_events(
                ["CommitMembershipProof"], proof_attrs):
            raise RuntimeError("membership proof key was already committed")
        rejected = self.submit_proof(client, height, mutated, path, value)
        self.evidence("forged-proof-mutated-gnokey.json", rejected)
        rejected_events = self.gno_events(["CommitMembershipProof"], proof_attrs)
        if (rejected["accepted"] or self.committed_proof(client, height, path) or
                rejected_events):
            raise RuntimeError("forged membership proof changed Gno state")
        control = self.submit_proof(client, height, proof, path, value)
        self.evidence("forged-proof-valid-gnokey.json", control)
        if not control["accepted"]:
            raise RuntimeError("valid membership proof was rejected")
        event = self.wait_events(["CommitMembershipProof"], proof_attrs, 1)[0]
        committed = self.committed_proof(client, height, path)
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
