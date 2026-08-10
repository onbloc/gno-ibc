#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
import urllib.request
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent
CONFIG_FILE = SCRIPT_DIR / "config" / "devnet.json"
HEX_ADDRESS = re.compile(r"^0x[0-9a-fA-F]{40}$")
PRIVATE_KEY = re.compile(r"^0x[0-9a-fA-F]{64}$")
UNION_ACCOUNT = re.compile(r"^union1[0-9a-z]{38}$")
UNION_CONTRACT = re.compile(r"^union1[0-9a-z]{58}$")
EVM_RELAYER_ROLE = "1"
EVM_RELAYER_KEYS = (
    "RELAYER_EMPTY_PRIVATE_KEY",
    "RELAYER_OFFLINE_PRIVATE_KEY",
    "RELAYER_RECOVERY_PRIVATE_KEY",
)


def devnet() -> dict[str, dict[str, str]]:
    return json.loads(CONFIG_FILE.read_text())


def config() -> dict[str, str]:
    values = {
        key: value for section in devnet().values() for key, value in section.items()
    }
    values.update({key: value for key, value in os.environ.items() if key in values})
    return values


def runner_config() -> dict[str, str]:
    values = devnet()["runner"]
    values.update({key: value for key, value in os.environ.items() if key in values})
    return values


def write_private_json(path: Path, values: dict[str, str]) -> None:
    path.touch(mode=0o600, exist_ok=True)
    path.chmod(0o600)
    path.write_text(json.dumps(values, indent=2) + "\n")


def require(values: dict[str, str], *names: str) -> None:
    missing = [name for name in names if not values.get(name)]
    if missing:
        raise SystemExit("missing required environment variables: " + ", ".join(missing))


def run(*args: str, cwd: Path | None = None, capture: bool = False, stdout=None) -> str:
    result = subprocess.run(
        args,
        cwd=cwd,
        check=True,
        text=True,
        stdout=subprocess.PIPE if capture else stdout,
    )
    return result.stdout.strip() if capture else ""


def emit(values: dict[str, str]) -> None:
    for name, value in values.items():
        if "\n" in value:
            raise SystemExit(f"{name} contains a newline")
        print(f"{name}={value}")


def nix_run_args(values: dict[str, str], target: str, *args: str) -> tuple[str, ...]:
    if values.get("E2E_NATIVE_NIX") == "true":
        return (
            "nix", "--accept-flake-config", "run", "--impure", f".#{target}", "--", *args
        )
    return ("./networks/run-linux-nix.sh", target, *args)


def validate(values: dict[str, str]) -> None:
    require(
        values,
        "UNION_VOYAGER_REVISION",
        "UNION_CHAIN_ID",
        "EVM_CHAIN_ID",
        "GNO_CHAIN_ID",
        "UNION_DEPLOYER",
        "EVM_SENDER",
        "GNO_RECIPIENT",
        "TRUSTED_MPT_PRIVATE_KEY",
        "UNION_PRIVATE_KEY",
        "EVM_PRIVATE_KEY",
        *EVM_RELAYER_KEYS,
        "GNO_PRIVATE_KEY",
    )
    for name in (
        "TRUSTED_MPT_PRIVATE_KEY",
        "UNION_PRIVATE_KEY",
        "EVM_PRIVATE_KEY",
        *EVM_RELAYER_KEYS,
        "GNO_PRIVATE_KEY",
    ):
        if not PRIVATE_KEY.fullmatch(values[name]):
            raise SystemExit(f"{name} must be a 0x-prefixed 32-byte private key")
    if not UNION_ACCOUNT.fullmatch(values["UNION_DEPLOYER"]):
        raise SystemExit("UNION_DEPLOYER is invalid")
    if not HEX_ADDRESS.fullmatch(values["EVM_SENDER"]):
        raise SystemExit("EVM_SENDER is invalid")


def extract_forge_address(logs: str, name: str) -> str:
    match = re.search(rf"{re.escape(name)}:\s*(0x[0-9a-fA-F]{{40}})", logs)
    if not match:
        raise SystemExit(f"forge logs contain no {name} address")
    return match.group(1)


def deploy_union(values: dict[str, str]) -> None:
    require(
        values,
        "UNION_VOYAGER_DIR",
        "UNION_DEPLOYER_IMAGE",
        "E2E_DEPLOYMENT_DIR",
        "UNION_PRIVATE_KEY",
        "UNION_DEPLOYER",
    )
    union_dir = Path(values["UNION_VOYAGER_DIR"]).resolve()
    image = values["UNION_DEPLOYER_IMAGE"]
    output = Path(values["E2E_DEPLOYMENT_DIR"]).resolve()
    output.mkdir(parents=True, exist_ok=True, mode=0o700)
    output.chmod(0o700)

    deployments = json.loads((union_dir / "deployments/deployments.json").read_text())
    deployment = deployments["union." + values["UNION_CHAIN_ID"]]
    deployer = deployment["deployer"]
    manager = next(
        address
        for address, contract in deployment["contracts"].items()
        if contract["name"] == "manager"
    )
    if deployer != values["UNION_DEPLOYER"]:
        raise SystemExit("configured Union deployer does not match the pinned devnet")

    base = (
        "docker",
        "run",
        "--rm",
        "--network",
        "host",
        "-v",
        f"{output}:/work/artifacts/deployment",
        image,
    )
    signer = run(
        *base,
        "cosmwasm-deployer",
        "address-of-private-key",
        "--private-key",
        values["UNION_PRIVATE_KEY"],
        "--bech32-prefix",
        "union",
        capture=True,
    )
    if signer != deployer:
        raise SystemExit("Union fixture key does not match the pinned devnet deployer")
    run(
        *base,
        "deploy-contract-union-devnet",
        "--allow-dirty",
        "--initial-admin",
        deployer,
        "--output",
        "/work/artifacts/deployment/manager.json",
    )
    run(
        *base,
        "union-devnet-deploy-full",
        "--allow-dirty",
        "--output",
        "/work/artifacts/deployment/contracts.json",
    )
    run(*base, "union-devnet-whitelist-relayers", deployer)

    if json.loads((output / "manager.json").read_text()) != manager:
        raise SystemExit("deployed Union manager does not match the pinned address")
    contracts = json.loads((output / "contracts.json").read_text())
    for address in (
        contracts.get("core", ""),
        contracts.get("lightclient", {}).get("trusted/evm/mpt", ""),
        contracts.get("app", {}).get("ucs03", ""),
    ):
        if not UNION_CONTRACT.fullmatch(address):
            raise SystemExit("Union deployment output is incomplete")


def grant_evm_relayer_roles(values: dict[str, str], manager: str) -> None:
    for name in EVM_RELAYER_KEYS:
        relayer = run(
            "cast", "wallet", "address", "--private-key", values[name], capture=True
        )
        run(
            "cast", "send", manager, "grantRole(uint64,address,uint32)",
            EVM_RELAYER_ROLE, relayer, "0",
            "--private-key", values["EVM_PRIVATE_KEY"],
            "--rpc-url", values["EVM_PACKET_RPC_URL"],
            stdout=sys.stderr,
        )


def configure_evm(values: dict[str, str]) -> None:
    require(
        values,
        "UNION_VOYAGER_DIR",
        "UNION_PROJECT",
        "EVM_PRIVATE_KEY",
        *EVM_RELAYER_KEYS,
        "EVM_SENDER",
        "EVM_CHAIN_ID",
        "EVM_PACKET_RPC_URL",
    )
    union_dir = Path(values["UNION_VOYAGER_DIR"]).resolve()
    project = values["UNION_PROJECT"]
    compose = ("docker", "compose", "-p", project)
    container = run(*compose, "ps", "-aq", "forge", cwd=union_dir, capture=True)
    if not container or run("docker", "wait", container, capture=True) != "0":
        raise SystemExit("EVM Forge deployment failed")
    logs = run(*compose, "logs", "--no-color", "forge", cwd=union_dir, capture=True)
    addresses = {
        name: extract_forge_address(logs, name)
        for name in (
            "Manager",
            "Deployer",
            "Sender",
            "IBCHandler",
            "UCS03",
            "Multicall",
        )
    }
    sender = addresses["Sender"]
    derived_sender = run(
        "cast",
        "wallet",
        "address",
        "--private-key",
        values["EVM_PRIVATE_KEY"],
        capture=True,
    )
    if (
        sender.lower() != values["EVM_SENDER"].lower()
        or sender.lower() != derived_sender.lower()
    ):
        raise SystemExit("EVM fixture key does not match the pinned devnet sender")

    run(
        *nix_run_args(
            values,
            "evm-scripts.devnet.script-register-clients",
            "--deployer_pk",
            addresses["Deployer"],
            "--sender_pk",
            sender,
        ),
        cwd=union_dir,
        stdout=sys.stderr,
    )
    handler = addresses["IBCHandler"]
    rpc = values["EVM_PACKET_RPC_URL"]
    grant_evm_relayer_roles(values, addresses["Manager"])
    cometbls = run(
        "cast",
        "call",
        handler,
        "clientRegistry(string)(address)",
        "cometbls",
        "--rpc-url",
        rpc,
        capture=True,
    )
    proof_lens = run(
        "cast",
        "call",
        handler,
        "clientRegistry(string)(address)",
        "proof-lens",
        "--rpc-url",
        rpc,
        capture=True,
    )
    for address in (cometbls, proof_lens):
        if not HEX_ADDRESS.fullmatch(address) or int(address, 16) == 0:
            raise SystemExit("EVM client registry is incomplete")
    if run("cast", "chain-id", "--rpc-url", rpc, capture=True) != values["EVM_CHAIN_ID"]:
        raise SystemExit("EVM chain ID does not match devnet.json")
    emit(
        {
            "EVM_IBC_HANDLER": handler.lower(),
            "EVM_MULTICALL": addresses["Multicall"].lower(),
            "EVM_COMETBLS_CLIENT_IMPL": cometbls.lower(),
            "EVM_PROOF_LENS_CLIENT_IMPL": proof_lens.lower(),
            "EVM_ZKGM_CONTRACT": addresses["UCS03"].lower(),
        }
    )


def deploy_test_token(values: dict[str, str]) -> None:
    required = (
        "EVM_PACKET_RPC_URL",
        "EVM_PRIVATE_KEY",
        "EVM_IBC_HANDLER",
        "EVM_MULTICALL",
        "EVM_COMETBLS_CLIENT_IMPL",
        "EVM_PROOF_LENS_CLIENT_IMPL",
        "EVM_ZKGM_CONTRACT",
    )
    require(values, *required)
    with tempfile.TemporaryDirectory() as output:
        raw = run(
            "forge",
            "create",
            "--root",
            ".",
            "--out",
            output,
            "--no-cache",
            "--rpc-url",
            values["EVM_PACKET_RPC_URL"],
            "--private-key",
            values["EVM_PRIVATE_KEY"],
            "--broadcast",
            "--json",
            "fixtures/TestERC20.sol:TestERC20",
            "--constructor-args",
            "Union E2E",
            "UE2E",
            "18",
            cwd=SCRIPT_DIR,
            capture=True,
        )
    token = json.loads(raw)["deployedTo"].lower()
    if not HEX_ADDRESS.fullmatch(token):
        raise SystemExit("Forge returned an invalid test token address")
    for address in (*(values[name] for name in required[2:]), token):
        code = run(
            "cast",
            "code",
            address,
            "--rpc-url",
            values["EVM_PACKET_RPC_URL"],
            capture=True,
        )
        if code == "0x":
            raise SystemExit(f"no EVM bytecode at {address}")
    emit({"EVM_TEST_ERC20": token})


def write_runner_config(values: dict[str, str]) -> None:
    require(
        values,
        "E2E_DEPLOYMENT_DIR",
        "E2E_ARTIFACT_DIR",
        "E2E_CONFIG_FILE",
    )
    deployment_dir = Path(values["E2E_DEPLOYMENT_DIR"])
    artifact_dir = Path(values["E2E_ARTIFACT_DIR"])
    config_file = Path(values["E2E_CONFIG_FILE"])
    contracts = json.loads((deployment_dir / "contracts.json").read_text())
    union_host = contracts["core"]
    with urllib.request.urlopen(
        f"http://127.0.0.1:1317/cosmwasm/wasm/v1/contract/{union_host}", timeout=30
    ) as response:
        contract = json.load(response)
    if int(contract["contract_info"]["code_id"]) <= 0:
        raise SystemExit("Union IBC host is not deployed")

    artifact_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
    artifact_dir.chmod(0o700)
    marker = artifact_dir / ".union-channel-e2e-artifacts"
    marker.write_text("union-channel-e2e-artifacts\n")
    workflow_run = artifact_dir / "workflow-run.json"
    workflow_run.write_text(
        json.dumps(
            {
                "run_id": os.environ.get("GITHUB_RUN_ID"),
                "run_attempt": os.environ.get("GITHUB_RUN_ATTEMPT"),
            }
        )
        + "\n"
    )
    marker.chmod(0o600)
    workflow_run.chmod(0o600)
    runner = runner_config()
    runner["UNION_IBC_HOST_CONTRACT"] = union_host
    runner["E2E_ARTIFACT_DIR"] = str(artifact_dir)
    if values.get("E2E_STATE_FILE"):
        runner["E2E_STATE_FILE"] = values["E2E_STATE_FILE"]
    require(runner, *(key for key in runner if key not in {"E2E_STATE_FILE"}))
    config_file.parent.mkdir(parents=True, exist_ok=True)
    write_private_json(config_file, runner)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "command",
        choices=(
            "export-env",
            "validate",
            "deploy-union",
            "configure-evm",
            "deploy-test-token",
            "write-runner-config",
        ),
    )
    args = parser.parse_args()
    values = config()
    values.update(os.environ)
    if args.command == "export-env":
        emit(config())
    elif args.command == "validate":
        validate(values)
    elif args.command == "deploy-union":
        deploy_union(values)
    elif args.command == "configure-evm":
        configure_evm(values)
    elif args.command == "deploy-test-token":
        deploy_test_token(values)
    else:
        write_runner_config(values)


if __name__ == "__main__":
    main()
