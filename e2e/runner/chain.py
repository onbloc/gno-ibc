from __future__ import annotations

import json
import os
import subprocess
import tempfile
import time
import urllib.request

from . import codec
from .constants import *
from .voyager import SCRIPT_DIR, command


class Chain:
    def __init__(self, config: dict, voyager, state: dict):
        self.c = config
        self.v = voyager
        self.state = state

    def evm_channel_topic(self) -> str:
        return f'0x{self.state["channels"]["evm"]:064x}'

    def gno_port_topic(self) -> str:
        return "0x" + self.c["GNO_ZKGM_PORT"].encode().hex()

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

    def total_supply(self, token: str) -> int:
        return int(self.cast("call", token, "totalSupply()(uint256)").split()[0])

    def block(self) -> int:
        return int(self.cast("block-number"))

    def qeval(self, expression: str) -> str:
        return command([
            "gnokey", "query", "vm/qeval", "-remote", self.c["GNO_PACKET_RPC_URL"],
            "-data", expression,
        ], timeout=self.c["COMMAND_TIMEOUT"])

    def gno_batch_commitment_cleared(self, packet_hash: str) -> bool:
        raw = self.qeval(
            'gno.land/r/onbloc/ibc/union/testing/e2e_setup.QueryBatchPacketCommitment("' +
            packet_hash.removeprefix("0x") + '")')

        return CLEARED_COMMITMENT in raw

    def voucher_balance(self, voucher: str, owner: str) -> int:
        raw = self.qeval(f'{self.c["GNO_ZKGM_PORT"]}.VoucherBalanceOf("{voucher}",address("{owner}"))')

        return codec.parse_int64(raw, "voucher balance")

    def voucher_supply(self, registry_key: str) -> int:
        raw = self.qeval(f'gno.land/r/demo/defi/grc20reg.MustGet("{registry_key}").TotalSupply()')

        return codec.parse_int64(raw, "voucher total supply")

    def gno_events(self, event_types: list[str], attrs: dict[str, str] | None = None,
                   realm: str | None = None) -> list[dict]:
        attrs = attrs or {}
        realm = realm or self.c["GNO_IBC_CORE_REALM"]
        query = codec.gno_events_query(event_types, attrs, realm)
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

        return codec.match_gno_events(payload, event_types, attrs, realm)

    def wait_events(self, event_types: list[str], attrs: dict[str, str], count: int,
                    voyager=None) -> list[dict]:
        v = voyager or self.v
        def query():
            events = self.gno_events(event_types, attrs)
            if len(events) > count:
                raise RuntimeError(f"Gno event count={len(events)}, want {count}")
            return events if len(events) == count else None
        return v.wait(query, "Gno " + "/".join(event_types))

    def evm_logs(self, address: str, from_block: int, topics: list) -> list[dict]:
        request = {"address": address, "fromBlock": hex(from_block), "toBlock": "latest",
                   "topics": topics}
        try:
            return json.loads(self.cast("rpc", "eth_getLogs", json.dumps(request, separators=(",", ":"))))
        except json.JSONDecodeError as error:
            raise RuntimeError("malformed EVM log response") from error

    def wait_evm_log(self, from_block: int, topics: list, label: str, voyager=None) -> dict:
        v = voyager or self.v
        def query():
            logs = self.evm_logs(self.c["EVM_IBC_HANDLER"], from_block, topics)
            if len(logs) > 1:
                raise RuntimeError(f"{label} count={len(logs)}, want one")
            return logs[0] if logs else None
        return v.wait(query, label)

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
        initializer = INITIALIZE_SELECTOR + initializer.removeprefix("0x")
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
        timeout_ns = timeout_ns or (time.time_ns() + DEFAULT_TIMEOUT_NS)

        receipt = self.receipt(
            "packet", "send", self.c["EVM_ZKGM_CONTRACT"].lower(),
            "send(uint32,uint64,uint64,bytes32,(uint8,uint8,bytes))",
            str(self.state["channels"]["evm"]), "0", str(timeout_ns), plan["salt"],
            f"(2,3,{operand})", "--private-key", self.c["EVM_PRIVATE_KEY"], "--json",
        )

        packet_hash = codec.packet_send_hash(
            receipt, self.c["EVM_IBC_HANDLER"], self.evm_channel_topic())

        return {"tx": receipt["transactionHash"], "packet_hash": packet_hash,
                "timeout_timestamp_ns": timeout_ns}

    def mint_approve_snapshot(self, plan: dict, amount: str) -> dict:
        mint = self.receipt("mint", "send", plan["token"], "mint(address,uint256)",
                            plan["sender"], amount, "--private-key", self.c["EVM_PRIVATE_KEY"], "--json")
        approve = self.receipt("approve", "send", plan["token"], "approve(address,uint256)",
                              self.c["EVM_ZKGM_CONTRACT"].lower(), amount,
                              "--private-key", self.c["EVM_PRIVATE_KEY"], "--json")
        before = {"sender": self.token_balance(plan["token"], plan["sender"]),
                  "escrow": self.token_balance(plan["token"], self.c["EVM_ZKGM_CONTRACT"]),
                  "recipient": self.voucher_balance(plan["voucher"], self.c["GNO_RECIPIENT"])}
        return {"mint_tx": mint["transactionHash"], "approve_tx": approve["transactionHash"],
                "before": before, "from_block": self.block()}

    def submit_erc20(self, timeout_seconds: int = 0) -> dict:
        plan = self.prepare_token(self.c["EVM_TEST_ERC20"], 18, self.state["channels"]["gno"])
        amount = self.c["EVM_TEST_AMOUNT"]
        prelude = self.mint_approve_snapshot(plan, amount)
        timeout = time.time_ns() + timeout_seconds * NS_PER_SECOND if timeout_seconds else None
        sent = self.send_token(plan, self.c["GNO_RECIPIENT"], amount, 0, timeout)
        return {**plan, **sent, "amount": amount, "recipient": self.c["GNO_RECIPIENT"],
                **prelude, "failed_work_baseline": self.state["failed_work"]["final"]}

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

    def native_balance(self, owner: str, denom: str = "ugnot") -> int:
        raw = command(["gnokey", "query", "bank/balances/" + owner,
                       "-remote", self.c["GNO_PACKET_RPC_URL"]],
                      timeout=self.c["COMMAND_TIMEOUT"])

        return codec.parse_native_balance(raw, denom)

    def proxy_address(self) -> str:
        raw = self.qeval(self.c["GNO_ZKGM_PORT"] + ".ProxyAddress()")

        return codec.parse_proxy_address(raw)

    def wrapped_plan(self, evm_channel: int, base: str = "ugnot") -> dict:
        sender = self.cast("wallet", "address", "--private-key", self.c["EVM_PRIVATE_KEY"]).lower()
        fao = self.cast("call", self.c["EVM_ZKGM_CONTRACT"], "FAO_IMPL()(address)").split()[0].lower()
        implementation = self.cast("call", fao, "ERC20_IMPL()(address)").split()[0].lower()
        tag = os.urandom(32).hex()
        initializer = self.cast(
            "abi-encode", "f(address,address,string,string,uint8)", sender,
            self.c["EVM_ZKGM_CONTRACT"].lower(), "Union Gno " + tag[:32], "UG" + tag[:6], "6")
        initializer = INITIALIZE_SELECTOR + initializer.removeprefix("0x")
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

    def channel_open_commitment(self, channel: int, connection: int,
                                counterparty_channel: int, version: str) -> dict:
        encoded_path = self.cast("abi-encode", "f(uint256,uint256)", "3", str(channel))
        path_hex = self.cast("keccak", encoded_path)

        tuple_value = f'(3,{connection},{counterparty_channel},{self.gno_port_topic()},{version})'
        encoded_value = self.cast(
            "abi-encode", "f((uint8,uint32,uint32,bytes,string))", tuple_value)
        value_hex = self.cast("keccak", encoded_value)
        commitment = self.cast("keccak", value_hex)

        return {"path": path_hex, "value_hash": value_hex, "commitment": commitment}

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
        timeout_ns = time.time_ns() + timeout_seconds * NS_PER_SECOND
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
        channel = self.evm_channel_topic()
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

        return {"tx": event["tx"], "acknowledgement": codec.acknowledgement(event["attrs"])}

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

        return codec.union_membership_min_height(payload, client_id, minimum, path)

    def committed_proof(self, client: int, height: int, path: bytes) -> str:
        raw = self.qeval(
            "gno.land/r/onbloc/ibc/union/testing/e2e_setup.QueryCommittedMembershipProof"
            f'({client},{height},"{path.hex()}")')

        return codec.parse_committed_proof(raw)

    def submit_proof(self, client: int, height: int, proof: bytes,
                     path: bytes, value: bytes) -> dict:
        args = ["go", "run", ".", self.c["GNO_IBC_CORE_REALM"],
                str(client), str(height), proof.hex(),
                path.hex(), value.hex(), self.c["GNO_CHAIN_ID"], self.c["GNO_PACKET_RPC_URL"]]
        result = subprocess.run(args, cwd=SCRIPT_DIR / "proof", text=True, capture_output=True,
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

    def relayer_address(self, private_key: str) -> str:
        address = self.cast("wallet", "address", "--private-key", private_key).lower()
        if int(self.cast("balance", address)) != 0:
            raise RuntimeError("relayer fixture must start with zero EVM balance")
        return address

    def tx_sender(self, tx_hash: str) -> str:
        return json.loads(self.cast("tx", tx_hash, "--json"))["from"].lower()

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
