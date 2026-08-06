import stat
import tempfile
import unittest
from pathlib import Path

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


if __name__ == "__main__":
    unittest.main()
