import unittest

from runner import codec


class CodecTest(unittest.TestCase):
    @staticmethod
    def acknowledgement_value(success: bool) -> str:
        payload = b"payload"
        header = bytearray(96)
        header[31] = int(success)
        header[63] = 64
        header[64:96] = len(payload).to_bytes(32, "big")

        return "0x" + (header + payload + bytes(32 - len(payload))).hex()

    def test_parse_int64(self):
        self.assertEqual(codec.parse_int64("(123 int64)", "x"), 123)

        with self.assertRaises(RuntimeError) as raised:
            codec.parse_int64("not an int64", "x")
        self.assertEqual(str(raised.exception), "malformed Gno x")

    def test_address_topic(self):
        self.assertEqual(codec.address_topic("0x" + "ab" * 20),
                         "0x" + "0" * 24 + "ab" * 20)

    def test_acknowledgement(self):
        self.assertEqual(codec.acknowledgement({"acknowledgement": "0xab"}), "0xab")
        self.assertEqual(codec.acknowledgement({
            "acknowledgement_size": "4",
            "acknowledgement[0]": "ab",
            "acknowledgement[1]": "cd",
        }), "abcd")

        with self.assertRaises(RuntimeError):
            codec.acknowledgement({
                "acknowledgement_size": "3",
                "acknowledgement[0]": "ab",
                "acknowledgement[1]": "cd",
            })

    def test_acknowledgement_success(self):
        self.assertEqual(codec.acknowledgement_success(self.acknowledgement_value(True)), True)
        self.assertEqual(codec.acknowledgement_success(self.acknowledgement_value(False)), False)

        with self.assertRaises(RuntimeError):
            codec.acknowledgement_success("0x00")
        with self.assertRaises(RuntimeError):
            codec.acknowledgement_success("not hex")

    def test_mutate_proof(self):
        proof = bytes(64) + (1).to_bytes(8, "little") + (3).to_bytes(8, "little") + b"mpt"

        mutated = codec.mutate_proof(proof)

        self.assertEqual(len(mutated), len(proof))
        self.assertEqual(sum(left != right for left, right in zip(proof, mutated)), 1)

        with self.assertRaises(RuntimeError):
            codec.mutate_proof(bytes(71))
        with self.assertRaises(RuntimeError) as raised:
            codec.mutate_proof(bytes(64) + (0).to_bytes(8, "little"))
        self.assertEqual(str(raised.exception), "encoded storage proof has no MPT node")

    def test_parse_native_balance(self):
        raw = 'data: "100ugnot,5foo"'

        self.assertEqual(codec.parse_native_balance(raw, "ugnot"), 100)
        self.assertEqual(codec.parse_native_balance(raw, "bar"), 0)
        with self.assertRaises(RuntimeError):
            codec.parse_native_balance("not a balance", "ugnot")

    def test_gno_events_query(self):
        query = codec.gno_events_query(["PacketSend"], {"packet_hash": "0x01"}, "realm")

        self.assertEqual(isinstance(query, str), True)
        self.assertEqual("PacketSend" in query, True)
        self.assertEqual("realm" in query, True)

    def test_packet_send_hash(self):
        handler = "0x" + "1" * 40
        channel = "0x" + "2" * 64
        packet_hash = "0x" + "3" * 64
        log = {
            "address": handler,
            "topics": [codec.PACKET_SEND_TOPIC, channel, packet_hash],
        }

        self.assertEqual(codec.packet_send_hash({"logs": [log]}, handler, channel), packet_hash)

        with self.assertRaises(RuntimeError):
            codec.packet_send_hash({"logs": []}, handler, channel)
        with self.assertRaises(RuntimeError):
            codec.packet_send_hash({"logs": [log, log]}, handler, channel)
        with self.assertRaises(RuntimeError):
            codec.packet_send_hash({"logs": [log]}, handler, "0x" + "4" * 64)


if __name__ == "__main__":
    unittest.main()
