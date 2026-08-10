import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "e2e.py"
sys.path.insert(0, str(ROOT))

from runner.voyager import Voyager


SCENARIOS = [
    "forged-proof-rejection",
    "erc20-to-gno",
    "amount-boundaries",
    "gno-to-evm",
    "relayer-insufficient-balance-failover",
    "relayer-offline-failover",
    "relayer-balance-recovery",
    "evm-to-gno-timeout-refund",
    "gno-to-evm-timeout-refund",
]


class E2ERunnerTest(unittest.TestCase):
    def cli(self, *args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, SCRIPT, *args],
            text=True,
            capture_output=True,
            check=False,
        )

    def test_lists_all_scenarios_in_execution_order(self):
        result = self.cli("list")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines(), SCENARIOS)

    def test_plan_adds_shared_packet_prerequisite_once(self):
        result = self.cli("plan", "amount-boundaries", "gno-to-evm")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            result.stdout.splitlines(),
            ["erc20-to-gno", "amount-boundaries", "gno-to-evm"],
        )

    def test_unknown_scenario_fails_before_external_commands(self):
        result = self.cli("plan", "missing")

        self.assertEqual(result.returncode, 2)
        self.assertIn("unknown scenario: missing", result.stderr)

    def test_run_rejects_unknown_scenario_before_reading_config(self):
        result = self.cli("run", "missing", "--config", "/does/not/exist")

        self.assertEqual(result.returncode, 2)
        self.assertIn("unknown scenario: missing", result.stderr)

    def test_preflight_rejects_public_config_permissions(self):
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory, "runner.json")
            config.write_text("{}")
            config.chmod(0o644)

            result = self.cli("preflight", "--config", str(config))

        self.assertEqual(result.returncode, 1)
        self.assertIn("runner config must have mode 0600", result.stderr)

    def test_preflight_rejects_zero_contract_before_rpc_calls(self):
        values = json.loads(Path(ROOT, "config", "devnet.json").read_text())["runner"]
        values.update({
            "UNION_IBC_HOST_CONTRACT": "union1contract",
            "EVM_IBC_HANDLER": "0x" + "0" * 40,
            "EVM_MULTICALL": "0x" + "2" * 40,
            "EVM_ZKGM_CONTRACT": "0x" + "3" * 40,
            "EVM_COMETBLS_CLIENT_IMPL": "0x" + "4" * 40,
            "EVM_PROOF_LENS_CLIENT_IMPL": "0x" + "5" * 40,
        })
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory, "runner.json")
            config.write_text(json.dumps(values))
            config.chmod(0o600)

            result = self.cli("preflight", "--config", str(config), "forged-proof-rejection")

        self.assertEqual(result.returncode, 1)
        self.assertIn("EVM_IBC_HANDLER must be a non-zero", result.stderr)

    def test_wait_reports_start_heartbeat_and_completion(self):
        messages = []
        clock = [0]
        responses = iter((None, None, None, {"ready": True}))

        def sleep(seconds):
            clock[0] += seconds

        voyager = Voyager({"TIMEOUT": 120, "POLL": 30}, messages.append)
        with (mock.patch("runner.voyager.time.monotonic", side_effect=lambda: clock[0]),
              mock.patch("runner.voyager.time.sleep", side_effect=sleep)):
            result = voyager.wait(lambda: next(responses), "packet acknowledgement")

        self.assertEqual(result, {"ready": True})
        self.assertEqual(messages, [
            "wait packet acknowledgement: started",
            "wait packet acknowledgement: pending (60s elapsed)",
            "wait packet acknowledgement: passed (90s elapsed)",
        ])


if __name__ == "__main__":
    unittest.main()
