from __future__ import annotations

import json
import os
import re
import subprocess
import tempfile
import time
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent.parent
VERSION = "ucs03-zkgm-0"
VOYAGER_BIN = "/output/voyager"
VOYAGER_CONFIG = "/run/voyager/config.jsonc"
OWNER_LABEL = "io.onbloc.gno-ibc.e2e.run"


def command(args: list[str], *, timeout: float, env: dict | None = None, stdin: str | None = None,
            check: bool = True) -> str:
    merged = os.environ.copy()
    if env:
        merged.update(env)
    try:
        result = subprocess.run(
            args, text=True, capture_output=True, timeout=timeout, env=merged,
            check=False, input=stdin,
        )
    except subprocess.TimeoutExpired as error:
        raise RuntimeError(f"command timed out: {args[0]}") from error
    if check and result.returncode:
        detail = result.stderr.strip() or result.stdout.strip()
        raise RuntimeError(f"command failed: {args[0]}: {detail[-2000:]}")
    return result.stdout.strip()


def walk(value, replace):
    if isinstance(value, str):
        return replace(value)
    if isinstance(value, list):
        return [walk(item, replace) for item in value]
    if isinstance(value, dict):
        return {key: walk(item, replace) for key, item in value.items()}
    return value


def render_voyager(config: dict, plain: list[int], proof: list[int]) -> str:
    root = json.loads(Path(SCRIPT_DIR, "config", "config.jsonc.template").read_text())
    replacements = {
        "__UNION_CHAIN_ID__": config["UNION_CHAIN_ID"],
        "__EVM_CHAIN_ID__": config["EVM_CHAIN_ID"],
        "__GNO_CHAIN_ID__": config["GNO_CHAIN_ID"],
        "__UNION_IBC_HOST_CONTRACT__": config["UNION_IBC_HOST_CONTRACT"],
        "__EVM_IBC_HANDLER__": config["EVM_IBC_HANDLER"],
        "__EVM_MULTICALL__": config["EVM_MULTICALL"],
        "__GNO_IBC_CORE_REALM__": config["GNO_IBC_CORE_REALM"],
        "__GALOIS_PROVER_ENDPOINT__": config["GALOIS_PROVER_ENDPOINT"],
        "__UNION_RPC_URL__": config["UNION_RPC_URL"],
        "__EVM_RPC_URL__": config["EVM_RPC_URL"],
        "__GNO_RPC_URL__": config["GNO_RPC_URL"],
        "__GNO_TX_INDEXER_RPC_URL__": config["GNO_TX_INDEXER_RPC_URL"],
        "__VOYAGER_DATABASE_URL__": config["VOYAGER_DATABASE_URL"],
        "__TRUSTED_MPT_PRIVATE_KEY__": config["TRUSTED_MPT_PRIVATE_KEY"],
        "__UNION_PRIVATE_KEY__": config["UNION_PRIVATE_KEY"],
        "__EVM_PRIVATE_KEY__": config["EVM_PRIVATE_KEY"],
        "__GNO_PRIVATE_KEY__": config["GNO_PRIVATE_KEY"],
    }

    def replace(value: str) -> str:
        value = value.replace("__VOYAGER_BIN_DIR__", "/output/release")
        for old, new in replacements.items():
            value = value.replace(old, new)
        return value

    root = walk(root, replace)
    client_modules = sorted(
        f'{item["info"]["client_type"]}/{item["info"]["ibc_interface"]}'
        for item in root.get("modules", {}).get("client", []))
    if client_modules != sorted((
        "cometbls/ibc-gno", "cometbls/ibc-solidity", "gno/ibc-cosmwasm",
        "proof-lens/ibc-solidity", "state-lens/ics23/mpt/ibc-gno",
        "trusted/evm/mpt/ibc-cosmwasm")):
        raise RuntimeError("Voyager client module set changed")
    state_modules = sorted(
        item["info"]["chain_id"] for item in root.get("modules", {}).get("state", []))
    if state_modules != sorted((config["UNION_CHAIN_ID"], config["EVM_CHAIN_ID"],
                                config["GNO_CHAIN_ID"])):
        raise RuntimeError("Voyager state module set changed")
    seen = set()
    for plugin in root["plugins"]:
        path = plugin["path"]
        if plugin["config"].get("chain_id") != config["EVM_CHAIN_ID"]:
            continue
        ids = None
        if path.endswith("voyager-plugin-transaction-batch"):
            ids, kind = plain, "plain"
        elif path.endswith("voyager-plugin-transaction-batch-proof-lens"):
            ids, kind = proof, "proof"
        if ids is not None:
            plugin["config"]["client_configs"] = [
                {"client_id": item, "min_batch_size": 1, "max_batch_size": 5,
                 "max_wait_time": {"nanos": 0, "secs": 10}}
                for item in ids
            ]
            seen.add(kind)
    rendered = json.dumps(root, indent=2) + "\n"
    if seen != {"plain", "proof"} or bool(plain) != bool(proof):
        raise RuntimeError("Voyager EVM client allowlists are invalid")
    if re.search(r"__[A-Z0-9_]+__", rendered):
        raise RuntimeError("rendered config contains an unresolved placeholder")
    return rendered


class Voyager:
    def __init__(self, config: dict, progress=None):
        self.config = config
        self.progress = progress or (lambda message: None)
        self.container = ""
        self.run_id = ""
        self.runtime_dir: tempfile.TemporaryDirectory | None = None
        self.image_id = ""
        self.rendered = ""

    def docker(self, *args: str, check: bool = True, timeout: float | None = None) -> str:
        return command(["docker", *args], timeout=timeout or self.config["COMMAND_TIMEOUT"], check=check)

    def call(self, *args: str) -> str:
        if not self.container:
            raise RuntimeError("Voyager is not running")
        for attempt in range(5):
            try:
                return self.docker(
                    "exec", "--env", "RUST_LOG=", self.container,
                    VOYAGER_BIN, "-c", VOYAGER_CONFIG, *args,
                )
            except RuntimeError as error:
                if "deadlock detected" not in str(error) or attempt == 4:
                    raise
                time.sleep(self.config["POLL"])
        raise RuntimeError("Voyager command remained deadlocked")

    def json(self, *args: str):
        try:
            return json.loads(self.call(*args))
        except json.JSONDecodeError as error:
            raise RuntimeError("malformed Voyager response") from error

    def start(self, rendered: str) -> None:
        self.rendered = rendered
        self.runtime_dir = tempfile.TemporaryDirectory(prefix="union-voyager-")
        directory = Path(self.runtime_dir.name)
        self.run_id = directory.name
        host_config = directory / "config.jsonc"
        host_config.write_text(rendered)
        host_config.chmod(0o600)
        if not self.image_id:
            self.image_id = self.docker(
                "image", "inspect", "--format", "{{.Id}}", self.config["VOYAGER_IMAGE"],
                check=False,
            )
            if not self.image_id:
                self.docker("pull", self.config["VOYAGER_IMAGE"])
                self.image_id = self.docker(
                    "image", "inspect", "--format", "{{.Id}}", self.config["VOYAGER_IMAGE"]
                )
            if not re.fullmatch(r"sha256:[0-9a-f]{64}", self.image_id):
                raise RuntimeError("malformed Voyager image ID")
            revision = self.docker(
                "image", "inspect", "--format",
                '{{index .Config.Labels "org.opencontainers.image.revision"}}', self.image_id,
            )
            if revision != self.config["UNION_VOYAGER_REVISION"]:
                raise RuntimeError("Voyager image revision does not match")
            entrypoint = self.docker(
                "image", "inspect", "--format", "{{index .Config.Entrypoint 0}}", self.image_id)
            if entrypoint != VOYAGER_BIN:
                raise RuntimeError("Voyager image entrypoint does not match")
        self.container = "union-channel-e2e-" + self.run_id
        self.docker(
            "run", "--detach", "--name", self.container,
            "--add-host", "host.docker.internal:host-gateway",
            "--label", f"{OWNER_LABEL}={self.run_id}",
            "--env", "RUST_LOG=" + self.config.get("VOYAGER_RUST_LOG", "info"),
            "--mount", f"type=bind,src={host_config},dst={VOYAGER_CONFIG},readonly",
            self.image_id, "-c", VOYAGER_CONFIG, "start",
        )
        self.wait(lambda: self.call("rpc", "info"), "Voyager RPC readiness")

    def restart(self, rendered: str) -> None:
        self.close()
        self.start(rendered)

    def close(self) -> None:
        cleanup_error = None
        deadline = time.monotonic() + self.config["CLEANUP_TIMEOUT"]

        def remaining() -> float:
            value = deadline - time.monotonic()
            if value <= 0:
                raise RuntimeError("Voyager cleanup timed out")
            return value

        try:
            if self.container:
                names = self.docker(
                    "ps", "-a", "--filter", f"name=^/{self.container}$", "--format", "{{.Names}}",
                    timeout=remaining())
                if names:
                    owner = self.docker(
                        "inspect", "--format", f'{{{{index .Config.Labels "{OWNER_LABEL}"}}}}',
                        self.container, timeout=remaining())
                    if owner != self.run_id:
                        raise RuntimeError("refusing to remove Voyager container not owned by this run")
                    try:
                        self.docker("stop", "--timeout", str(self.config["STOP_TIMEOUT"]),
                                    self.container, timeout=remaining())
                    except RuntimeError as error:
                        cleanup_error = error
                    try:
                        self.docker("rm", self.container, timeout=remaining())
                    except RuntimeError as error:
                        cleanup_error = cleanup_error or error
                        try:
                            self.docker("rm", "--force", self.container, timeout=remaining())
                        except RuntimeError as force_error:
                            cleanup_error = cleanup_error or force_error
                        else:
                            self.container = ""
                    else:
                        self.container = ""
                else:
                    self.container = ""
        finally:
            if self.runtime_dir:
                self.runtime_dir.cleanup()
                self.runtime_dir = None
        if cleanup_error:
            raise cleanup_error

    def logs(self) -> str:
        if not self.container:
            return ""
        return command(
            ["docker", "logs", "--tail", "2000", self.container],
            timeout=self.config["CLEANUP_TIMEOUT"], check=False,
        )

    def wait(self, query, label: str):
        started = time.monotonic()
        deadline = started + self.config["TIMEOUT"]
        next_report = started + 60
        last = None
        self.progress(f"wait {label}: started")
        while time.monotonic() < deadline:
            try:
                value = query()
                if value is not None:
                    elapsed = int(time.monotonic() - started)
                    self.progress(f"wait {label}: passed ({elapsed}s elapsed)")
                    return value
            except RuntimeError as error:
                last = error
            now = time.monotonic()
            if now >= next_report:
                self.progress(f"wait {label}: pending ({int(now - started)}s elapsed)")
                next_report = now + 60
            time.sleep(self.config["POLL"])
        raise RuntimeError(f"{label} timed out" + (f": {last}" if last else ""))

    def submit(self, operation: dict) -> None:
        self.call("q", "e", json.dumps(operation, separators=(",", ":")))

    def latest_height(self, chain: str, finalized: bool = False) -> str:
        args = ["rpc", "latest-height", chain]
        if finalized:
            args.append("--finalized")
        value = self.json(*args)
        if isinstance(value, dict):
            value = value.get("height", value.get("revision_height"))
        value = str(value).strip('"')
        if not value or not value.split("-")[-1].isdigit():
            raise RuntimeError("malformed Voyager height")
        return value

    def index(self, chain: str, from_height: str = "") -> None:
        args = ["index", chain]
        if from_height:
            args += ["--from", from_height]
        self.call(*args, "-e")

    def next_id(self, chain: str, kind: str) -> int:
        for item in range(1, 100000):
            path = {"client": "client-info", "connection": "connection", "channel": "channel"}[kind]
            raw = self.call("rpc", "ibc-state", chain, json.dumps({path: {f"{kind}_id": item}})) \
                if kind != "client" else self.call("rpc", "client-info", chain, str(item))
            try:
                value = json.loads(raw)
            except json.JSONDecodeError:
                value = raw
            if value is None or value == "null" or value == {"state": None}:
                return item
        raise RuntimeError(f"cannot find next {kind} id")

    def create_client(self, chain: str, counterparty: str, client_type: str,
                      interface: str, *, config: dict | None = None,
                      height: str = "", failed_baseline: int = 0,
                      repaired: list[int] | None = None) -> int:
        repaired = repaired if repaired is not None else []
        expected = self.next_id(chain, "client")
        label = f"client {chain}/{expected} ({client_type})"
        self.progress(f"{label}: creating")
        args = ["msg", "create-client", "--on", chain, "--tracking", counterparty,
                "--ibc-interface", interface, "--client-type", client_type]
        if config is not None:
            args += ["--config", json.dumps(config, separators=(",", ":"))]
        if height:
            args += ["--height", height]
        self.call(*args, "-e")
        deadline = time.monotonic() + self.config["TIMEOUT"]
        refresh_at = time.monotonic() + self.config["EVM_REFRESH"]
        refreshes = 0
        while time.monotonic() < deadline:
            matches = self.failed_creates(chain, expected, client_type, failed_baseline, repaired)
            if matches:
                self.restart(self.rendered)
                for failed_id in matches:
                    self.call("queue", "query-failed-by-id", str(failed_id), "-e")
                    repaired.append(failed_id)
            info = self.client_info(chain, expected)
            if info:
                meta = self.json("rpc", "client-meta", chain, str(expected))
                status_query = json.dumps(
                    {"client_status": {"client_id": expected}}, separators=(",", ":"))
                status = self.json("rpc", "query", chain, status_query)
                if (info.get("client_type") != client_type or
                        info.get("ibc_interface") != interface or
                        meta.get("counterparty_chain_id") != counterparty or
                        str(status).lower() != "active"):
                    raise RuntimeError(f"created client relation mismatch: {chain}/{expected}")
                break
            if (chain == self.config["EVM_CHAIN_ID"] and refreshes < 3 and
                    time.monotonic() >= refresh_at):
                self.restart(self.rendered)
                refreshes += 1
                refresh_at = time.monotonic() + self.config["EVM_REFRESH"]
            time.sleep(self.config["POLL"])
        else:
            raise RuntimeError(f"client {chain}/{expected} timed out")
        self.progress(f"{label}: active")
        return expected

    def failed_rows(self) -> list[dict]:
        rows = self.json("queue", "query-failed", "--per-page", "100")
        return rows.get("items", rows.get("data", [])) if isinstance(rows, dict) else rows

    def failed_creates(self, chain: str, client_id: int, client_type: str,
                       baseline: int, repaired: list[int]) -> list[int]:
        matches = []
        for row in self.failed_rows():
            failed_id = int(row["id"])
            try:
                value = row["item"]["@value"]["@value"]
                event = value["message"]["@value"]["event"]
                fields = event["@value"]
            except (KeyError, TypeError):
                continue
            if (failed_id > baseline and failed_id not in repaired and
                    value.get("plugin", "").endswith("/" + chain) and
                    event.get("@type") == "create_client" and
                    int(fields.get("client_id", -1)) == client_id and
                    fields.get("client_type") == client_type):
                matches.append(failed_id)
        return sorted(matches)

    def client_info(self, chain: str, client_id: int):
        try:
            value = self.json("rpc", "client-info", chain, str(client_id))
        except RuntimeError as error:
            detail = str(error).lower()
            if "client" in detail and "not found" in detail:
                return None
            raise
        return value if value else None

    def client_height(self, chain: str, client_id: int) -> str:
        meta = self.json("rpc", "client-meta", chain, str(client_id))
        return str(meta["counterparty_height"])

    def failed_work(self) -> int:
        return max((int(row.get("id", 0)) for row in self.failed_rows()), default=0)

    def active_queue(self) -> dict:
        value = self.json("queue", "stats")
        if int(value.get("total", -1)) < 0 or int(value.get("ready", -1)) < 0:
            raise RuntimeError("malformed Voyager active queue stats")
        return value

    def ibc_state(self, chain: str, kind: str, item: int):
        response = self.json(
            "rpc", "ibc-state", chain,
            json.dumps({kind: {kind + "_id": item}}, separators=(",", ":")),
        )
        return response.get("state") if isinstance(response, dict) else None


def operation(chain: str, kind: str, value: dict) -> dict:
    return {
        "@type": "call", "@value": {
            "@type": "submit_tx", "@value": {
                "chain_id": chain,
                "datagrams": [{
                    "ibc_spec_id": "ibc-union",
                    "datagram": {"@type": kind, "@value": value},
                }],
            },
        },
    }
