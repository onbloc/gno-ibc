import unittest

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


if __name__ == "__main__":
    unittest.main()
