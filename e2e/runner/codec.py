import json
import re

from .constants import HASH, PACKET_SEND_TOPIC


def address_topic(address: str) -> str:
    return "0x" + "0" * 24 + address.removeprefix("0x")


def parse_int64(raw: str, label: str) -> int:
    match = re.search(r"\(([0-9]+)\s+int64\)", raw)

    if not match:
        raise RuntimeError(f"malformed Gno {label}")

    return int(match.group(1))


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


def parse_native_balance(raw: str, denom: str) -> int:
    match = re.search(r'data: "([^"]*)"', raw)

    if not match:
        raise RuntimeError("malformed Gno native balance")

    for coin in match.group(1).split(","):
        found = re.fullmatch(r"([0-9]+)(.+)", coin.strip())

        if found and found.group(2) == denom:
            return int(found.group(1))

    return 0


def parse_proxy_address(raw: str) -> str:
    match = re.search(r'"(g1[0-9a-z]{38})"', raw)

    if not match:
        raise RuntimeError("malformed Gno proxy address")

    return match.group(1)


def parse_committed_proof(raw: str) -> str:
    match = re.search(r'"(0x[0-9a-f]{64})"', raw)

    if match:
        return match.group(1)

    if '("" string)' in raw:
        return ""

    raise RuntimeError("malformed committed membership proof response")


def gno_events_query(event_types: list[str], attrs: dict[str, str], realm: str) -> str:
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

    return (
        "{ getTransactions(where: { success: { eq: true } response: { events: { _or: [" +
        " ".join(conditions) +
        "] } } } order: { heightAndIndex: DESC }) { hash block_height response { events { "
        "... on GnoEvent { type pkg_path attrs { key value } } } } } }"
    )


def match_gno_events(payload: dict, event_types: list[str], attrs: dict[str, str],
                     realm: str) -> list[dict]:
    matches = []

    for tx in payload["data"]["getTransactions"]:
        for event in tx["response"]["events"]:
            pairs = {item["key"]: item["value"] for item in event.get("attrs", [])}

            if (event.get("pkg_path") == realm and event.get("type") in event_types and
                    all(pairs.get(key) == value for key, value in attrs.items())):
                matches.append({"type": event["type"], "tx": tx["hash"],
                                "height": int(tx["block_height"]), "attrs": pairs})

    return matches


def union_membership_min_height(payload: dict, client_id: int, minimum: int,
                                path: str) -> int:
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


def packet_send_hash(receipt: dict, ibc_handler: str, channel_topic: str) -> str:
    logs = [item for item in receipt["logs"]
            if item.get("address", "").lower() == ibc_handler.lower()
            and item.get("topics", [""])[0].lower() == PACKET_SEND_TOPIC]

    if len(logs) != 1:
        raise RuntimeError("packet transaction did not emit exactly one PacketSend")

    if logs[0]["topics"][1].lower() != channel_topic:
        raise RuntimeError("PacketSend channel does not match")

    packet_hash = logs[0]["topics"][2]

    if not HASH.fullmatch(packet_hash):
        raise RuntimeError("malformed packet hash")

    return packet_hash
