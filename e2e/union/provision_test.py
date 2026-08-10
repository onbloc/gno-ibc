import stat
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import provision


class ProvisionTest(unittest.TestCase):
    def test_devnet_config_is_valid(self):
        provision.validate(provision.config())

    def test_extracts_forge_address_without_gnu_tools(self):
        logs = "== Logs ==\n  Sender:  0xBe68fC2d8249eb60bfCf0e71D5A0d2F2e292c4eD\n"
        self.assertEqual(
            provision.extract_forge_address(logs, "Sender"),
            "0xBe68fC2d8249eb60bfCf0e71D5A0d2F2e292c4eD",
        )

    def test_writes_private_json(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "runner.json"
            provision.write_private_json(output, {"UNION_CHAIN_ID": "test"})
            self.assertEqual(stat.S_IMODE(output.stat().st_mode), 0o600)

    def test_runner_config_excludes_provisioning_values(self):
        self.assertNotIn("UNION_DEPLOYER", provision.runner_config())

    def test_uses_native_nix_when_requested(self):
        self.assertEqual(
            provision.nix_run_args(
                {"E2E_NATIVE_NIX": "true"}, "package", "argument"
            ),
            (
                "nix",
                "--accept-flake-config",
                "run",
                "--impure",
                ".#package",
                "--",
                "argument",
            ),
        )

    def test_grants_relayer_role_to_fixture_signers(self):
        values = provision.config()
        manager = "0x" + "f" * 40
        relayers = ["0x" + digit * 40 for digit in "123"]
        with mock.patch.object(
            provision,
            "run",
            side_effect=[value for address in relayers for value in (address, "")],
        ) as run:
            provision.grant_evm_relayer_roles(values, manager)

        self.assertEqual(
            [call.args[4] for call in run.call_args_list[::2]],
            [values[name] for name in provision.EVM_RELAYER_KEYS],
        )
        self.assertEqual(
            [call.args[2:7] for call in run.call_args_list[1::2]],
            [
                (
                    manager,
                    "grantRole(uint64,address,uint32)",
                    provision.EVM_RELAYER_ROLE,
                    address,
                    "0",
                )
                for address in relayers
            ],
        )


if __name__ == "__main__":
    unittest.main()
