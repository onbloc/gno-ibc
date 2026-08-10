#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import stat
import sys
from pathlib import Path

from runner.scenarios import Runner
from runner.voyager import SCRIPT_DIR, command


DEFAULT_CONFIG = Path(os.getenv("E2E_CONFIG_FILE", SCRIPT_DIR / "runner.json"))
SCENARIOS = (
    "forged-proof-rejection",
    "erc20-to-gno",
    "amount-boundaries",
    "gno-to-evm",
    "relayer-insufficient-balance-failover",
    "relayer-offline-failover",
    "relayer-balance-recovery",
    "evm-to-gno-timeout-refund",
    "gno-to-evm-timeout-refund",
)
PACKET_PREREQUISITES = {"amount-boundaries", "gno-to-evm"}
REQUIRED = (
    "UNION_CHAIN_ID", "EVM_CHAIN_ID", "GNO_CHAIN_ID", "UNION_VOYAGER_REVISION",
    "UNION_IBC_HOST_CONTRACT", "EVM_IBC_HANDLER", "EVM_MULTICALL",
    "EVM_COMETBLS_CLIENT_IMPL", "EVM_PROOF_LENS_CLIENT_IMPL", "GNO_IBC_CORE_REALM",
    "GNO_ZKGM_PORT", "EVM_ZKGM_CONTRACT", "GALOIS_PROVER_ENDPOINT", "UNION_RPC_URL",
    "EVM_RPC_URL", "GNO_RPC_URL", "GNO_TX_INDEXER_RPC_URL", "VOYAGER_DATABASE_URL",
    "TRUSTED_MPT_PRIVATE_KEY", "UNION_PRIVATE_KEY", "EVM_PRIVATE_KEY", "GNO_PRIVATE_KEY",
)


def progress(message: str) -> None:
    print("e2e: " + message, file=sys.stderr, flush=True)


def plan(selected: list[str]) -> list[str]:
    unknown = next((name for name in selected if name not in SCENARIOS), None)
    if unknown:
        raise ValueError(f"unknown scenario: {unknown}")
    wanted = set(selected)
    if wanted & PACKET_PREREQUISITES:
        wanted.add("erc20-to-gno")
    return [name for name in SCENARIOS if name in wanted]


def load_config(path: Path, packet: bool) -> dict:
    info = path.lstat()
    if not stat.S_ISREG(info.st_mode) or path.is_symlink():
        raise RuntimeError("runner config must be a regular non-symlink file")
    if stat.S_IMODE(info.st_mode) != 0o600:
        raise RuntimeError("runner config must have mode 0600")
    try:
        config = json.loads(path.read_text())
        pinned = json.loads(Path(SCRIPT_DIR, "config", "devnet.json").read_text())["runner"]
    except (OSError, json.JSONDecodeError, KeyError) as error:
        raise RuntimeError(f"cannot read runner config: {error}") from error
    for name in ("UNION_VOYAGER_REVISION", "UNION_CHAIN_ID", "EVM_CHAIN_ID", "GNO_CHAIN_ID"):
        if config.get(name) != pinned.get(name):
            raise RuntimeError("runner config pinned values do not match devnet.json")
    for name in ("RELAYER_EMPTY_PRIVATE_KEY", "RELAYER_OFFLINE_PRIVATE_KEY", "RELAYER_RECOVERY_PRIVATE_KEY"):
        config[name] = pinned[name]
    for name in REQUIRED:
        if not config.get(name):
            raise RuntimeError(f"missing required runner config value: {name}")
    if packet:
        for name in ("EVM_TEST_ERC20", "GNO_RECIPIENT", "EVM_TEST_AMOUNT"):
            if not config.get(name):
                raise RuntimeError(f"missing required packet runner config value: {name}")
    for name, fallback in (
        ("UNION_PACKET_RPC_URL", "UNION_RPC_URL"),
        ("EVM_PACKET_RPC_URL", "EVM_RPC_URL"),
        ("GNO_PACKET_RPC_URL", "GNO_RPC_URL"),
        ("GNO_PACKET_INDEXER_RPC_URL", "GNO_TX_INDEXER_RPC_URL"),
    ):
        config[name] = config.get(name) or config[fallback]
    artifact = Path(config.get("E2E_ARTIFACT_DIR") or "channel-e2e-artifacts")
    config["E2E_ARTIFACT_DIR"] = str(artifact if artifact.is_absolute() else SCRIPT_DIR / artifact)
    state_file = Path(config.get("E2E_STATE_FILE") or artifact / "state.json")
    config["E2E_STATE_FILE"] = str(state_file if state_file.is_absolute() else SCRIPT_DIR / state_file)
    config["VOYAGER_IMAGE"] = config.get("VOYAGER_IMAGE") or "union-voyager-e2e:" + config["UNION_VOYAGER_REVISION"][:12]
    config["TIMEOUT"] = int(os.getenv("E2E_TIMEOUT_SECONDS", "900"))
    config["POLL"] = int(os.getenv("E2E_POLL_SECONDS", "2"))
    config["COMMAND_TIMEOUT"] = int(os.getenv("VOYAGER_COMMAND_TIMEOUT_SECONDS", "120"))
    config["CLEANUP_TIMEOUT"] = int(os.getenv("E2E_CLEANUP_TIMEOUT_SECONDS", "30"))
    config["STOP_TIMEOUT"] = int(os.getenv("VOYAGER_STOP_TIMEOUT_SECONDS", "10"))
    config["EVM_REFRESH"] = int(os.getenv("VOYAGER_EVM_REFRESH_SECONDS", "60"))
    if (any(config[name] <= 0 for name in ("TIMEOUT", "COMMAND_TIMEOUT", "CLEANUP_TIMEOUT")) or
            config["POLL"] < 0 or config["STOP_TIMEOUT"] < 0 or config["EVM_REFRESH"] < 0 or
            config["STOP_TIMEOUT"] > config["CLEANUP_TIMEOUT"]):
        raise RuntimeError("runner timeout values are invalid")
    if not re.fullmatch(r"[1-9][0-9]*", config["EVM_CHAIN_ID"]):
        raise RuntimeError("EVM_CHAIN_ID must be a positive decimal integer")
    if not re.fullmatch(r"[0-9a-f]{40}", config["UNION_VOYAGER_REVISION"]):
        raise RuntimeError("UNION_VOYAGER_REVISION must be a lowercase 40-character commit SHA")
    if not re.fullmatch(r"gno\.land/r/[0-9A-Za-z_./-]+", config["GNO_ZKGM_PORT"]):
        raise RuntimeError("GNO_ZKGM_PORT must be a gno.land/r/... realm path")
    for name in ("EVM_IBC_HANDLER", "EVM_MULTICALL", "EVM_ZKGM_CONTRACT",
                 "EVM_COMETBLS_CLIENT_IMPL", "EVM_PROOF_LENS_CLIENT_IMPL"):
        if not re.fullmatch(r"0x[0-9a-fA-F]{40}", config[name]) or int(config[name], 16) == 0:
            raise RuntimeError(f"{name} must be a non-zero 20-byte hex address")
    for name in ("TRUSTED_MPT_PRIVATE_KEY", "UNION_PRIVATE_KEY", "EVM_PRIVATE_KEY",
                 "GNO_PRIVATE_KEY", "RELAYER_EMPTY_PRIVATE_KEY", "RELAYER_OFFLINE_PRIVATE_KEY",
                 "RELAYER_RECOVERY_PRIVATE_KEY"):
        if not re.fullmatch(r"0x[0-9a-fA-F]{64}", config[name]):
            raise RuntimeError(f"{name} must be a 0x-prefixed 32-byte private key")
    if packet:
        if not re.fullmatch(r"0x[0-9a-fA-F]{40}", config["EVM_TEST_ERC20"]):
            raise RuntimeError("EVM_TEST_ERC20 must be a 20-byte hex address")
        if not re.fullmatch(r"g1[0-9a-z]{38}", config["GNO_RECIPIENT"]):
            raise RuntimeError("GNO_RECIPIENT must be a Gno bech32 address")
        amount = config["EVM_TEST_AMOUNT"]
        if (not re.fullmatch(r"[1-9][0-9]*000000000000", amount) or
                int(amount[:-12]) > 9223372036854775807):
            raise RuntimeError("EVM_TEST_AMOUNT must scale by 10^12 into Gno int64")
        for name in ("UNION_PACKET_RPC_URL", "EVM_PACKET_RPC_URL", "GNO_PACKET_RPC_URL",
                     "GNO_PACKET_INDEXER_RPC_URL"):
            if any(character in config[name] for character in ('\n', '"', '\\')):
                raise RuntimeError(f"{name} contains an unsupported character")
    return config


def preflight(config_path: Path, selected: list[str]) -> None:
    selected = plan(selected or list(SCENARIOS))
    config = load_config(config_path, any(name != "forged-proof-rejection" for name in selected))
    required = {"docker", "cast", "gnokey"}
    if "amount-boundaries" in selected:
        required.add("forge")
    if "forged-proof-rejection" in selected:
        required.add("go")
    missing = sorted(name for name in required if not shutil.which(name))
    if missing:
        raise RuntimeError("missing required command: " + ", ".join(missing))
    rpc = {"ETH_RPC_URL": config["EVM_PACKET_RPC_URL"]}
    for client_type, expected in (("cometbls", config["EVM_COMETBLS_CLIENT_IMPL"]),
                                  ("proof-lens", config["EVM_PROOF_LENS_CLIENT_IMPL"])):
        actual = command(["cast", "call", config["EVM_IBC_HANDLER"],
                          "clientRegistry(string)(address)", client_type],
                         timeout=config["COMMAND_TIMEOUT"], env=rpc).split()[0]
        if actual.lower() != expected.lower() or int(actual, 16) == 0:
            raise RuntimeError(f"EVM {client_type} registry does not match runner config")


def main() -> int:
    parser = argparse.ArgumentParser()
    subcommands = parser.add_subparsers(dest="command", required=True)
    subcommands.add_parser("list")
    plan_parser = subcommands.add_parser("plan")
    plan_parser.add_argument("scenarios", nargs="+")
    preflight_parser = subcommands.add_parser("preflight")
    preflight_parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    preflight_parser.add_argument("scenarios", nargs="*")
    setup_parser = subcommands.add_parser("setup")
    setup_parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    setup_parser.add_argument("--resume", action="store_true")
    run_parser = subcommands.add_parser("run")
    run_parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    run_parser.add_argument("--resume", action="store_true")
    run_parser.add_argument("scenarios", nargs="*")
    args = parser.parse_args()

    if args.command == "list":
        print(*SCENARIOS, sep="\n")
        return 0
    try:
        if args.command == "plan":
            print(*plan(args.scenarios), sep="\n")
        elif args.command == "preflight":
            progress("preflight: started")
            preflight(args.config, args.scenarios)
            progress("preflight: passed")
            print("preflight passed")
        elif args.command == "setup":
            config = load_config(args.config, False)
            missing = sorted(name for name in ("docker",) if not shutil.which(name))
            if missing:
                raise RuntimeError("missing required command: " + ", ".join(missing))
            Runner(config, [], args.resume).run()
            print("topology setup passed")
        else:
            scenarios = plan(args.scenarios or list(SCENARIOS))
            progress("preflight: started")
            preflight(args.config, scenarios)
            progress("preflight: passed")
            config = load_config(
                args.config, any(name != "forged-proof-rejection" for name in scenarios))
            Runner(config, scenarios, args.resume).run()
            print("all selected scenarios passed")
        return 0
    except (OSError, RuntimeError, ValueError) as error:
        print(error, file=sys.stderr)
        return 2 if isinstance(error, ValueError) else 1


if __name__ == "__main__":
    raise SystemExit(main())
