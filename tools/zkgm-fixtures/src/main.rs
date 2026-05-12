//! Emit handler/dispatch end-to-end scenario fixtures for the gno zkgm tests.
//!
//! Each scenario describes a full `ZkgmPacket` envelope (salt, path, one of
//! the four opcodes as the top-level instruction) paired with the canonical
//! success/failure `Ack` envelope that the handler should emit on the happy
//! path. The gno handler/dispatch tests load this file and:
//!   1. Build the same `ZkgmPacket` via the in-tree types.
//!   2. Encode it and assert byte-equality with `packet_data_hex`.
//!   3. Decode `packet_data_hex` and assert structural equality with the
//!      constructed packet.
//!   4. Build the matching `Ack` (success and failure variants) and assert
//!      byte-equality with `success_ack_hex` / `failure_ack_hex`.
//!
//! This is wire-level ground truth; state-dependent handler effects
//! (escrow balance, voucher mint, rate-limit bucket state, event emission)
//! stay in the pure gno handler tests since they require gno-side state.
//! Together with `abi-fixtures` (which pins per-struct encoding correctness
//! for each isolated body), these scenarios pin the full envelope shape +
//! the ack pairing convention.
//!
//! The `sol!` block, constants, and `_params` flavor convention are a
//! verbatim copy of `union/cosmwasm/app/ucs03-zkgm/src/com.rs` — the same
//! source `abi-fixtures` keeps in sync. If Union ever changes the wire
//! format, regenerate both fixtures.
//!
//! Output: a JSON array of `Scenario` records on stdout.
//! Regenerate with `make refresh-zkgm-scenarios` from the repo root.

use alloy_primitives::{Bytes, FixedBytes, U256};
use alloy_sol_types::{abi::TokenSeq, sol, SolType, SolValue};
use serde::Serialize;
use serde_json::{json, Value};

// ───────────────────────────────────────────────────────────────────────
// Constants (verbatim from Union `ucs03-zkgm` `com.rs`)
// ───────────────────────────────────────────────────────────────────────

const INSTR_VERSION_0: u8 = 0x00;
const INSTR_VERSION_1: u8 = 0x01;
const INSTR_VERSION_2: u8 = 0x02;

const OP_FORWARD: u8 = 0x00;
const OP_CALL: u8 = 0x01;
const OP_BATCH: u8 = 0x02;
const OP_TOKEN_ORDER: u8 = 0x03;

const TAG_ACK_FAILURE: u64 = 0;
const TAG_ACK_SUCCESS: u64 = 1;

const FILL_TYPE_PROTOCOL: u64 = 0xB0CAD0;
const FILL_TYPE_MARKETMAKER: u64 = 0xD1CEC45E;

const TOKEN_ORDER_KIND_INITIALIZE: u8 = 0x00;
const TOKEN_ORDER_KIND_ESCROW: u8 = 0x01;
const TOKEN_ORDER_KIND_UNESCROW: u8 = 0x02;
const TOKEN_ORDER_KIND_SOLVE: u8 = 0x03;

const UNIVERSAL_ERROR: &[u8] = b"UNIVERSAL_ERROR";

sol! {
    #[derive(Debug)]
    struct ZkgmPacket {
        bytes32 salt;
        uint256 path;
        Instruction instruction;
    }

    #[derive(Debug)]
    struct Instruction {
        uint8 version;
        uint8 opcode;
        bytes operand;
    }

    struct Forward {
        uint256 path;
        uint64 timeout_height;
        uint64 timeout_timestamp;
        Instruction instruction;
    }

    struct Call {
        bytes sender;
        bool eureka;
        bytes contract_address;
        bytes contract_calldata;
    }

    struct Batch {
        Instruction[] instructions;
    }

    #[derive(Debug, PartialEq)]
    struct TokenOrderV1 {
        bytes sender;
        bytes receiver;
        bytes base_token;
        uint256 base_amount;
        string base_token_symbol;
        string base_token_name;
        uint8 base_token_decimals;
        uint256 base_token_path;
        bytes quote_token;
        uint256 quote_amount;
    }

    #[derive(Debug, PartialEq)]
    struct TokenOrderV2 {
        bytes sender;
        bytes receiver;
        bytes base_token;
        uint256 base_amount;
        bytes quote_token;
        uint256 quote_amount;
        uint8 kind;
        bytes metadata;
    }

    #[derive(Debug, PartialEq)]
    struct TokenMetadata {
        bytes implementation;
        bytes initializer;
    }

    #[derive(Debug)]
    struct Ack {
        uint256 tag;
        bytes inner_ack;
    }

    struct BatchAck {
        bytes[] acknowledgements;
    }

    #[derive(Debug)]
    struct TokenOrderAck {
        uint256 fill_type;
        bytes market_maker;
    }
}

// ───────────────────────────────────────────────────────────────────────
// Helpers
// ───────────────────────────────────────────────────────────────────────

fn hex0x(bytes: &[u8]) -> String {
    format!("0x{}", hex::encode(bytes))
}

// `abi_encode_params` (not plain `abi_encode`) — see abi-fixtures README:
// Union encodes ZKGM wire bytes via the _params flavor. The two differ by
// a 32-byte head_offset prefix; every gno encoder/decoder uses _params.
fn encode_params<T>(value: &T) -> Vec<u8>
where
    T: SolValue,
    for<'a> <<T as SolValue>::SolType as SolType>::Token<'a>: TokenSeq<'a>,
{
    value.abi_encode_params()
}

fn instruction(version: u8, opcode: u8, operand: Vec<u8>) -> Instruction {
    Instruction {
        version,
        opcode,
        operand: Bytes::from(operand),
    }
}

fn pack_zkgm(salt: FixedBytes<32>, path: U256, instr: Instruction) -> ZkgmPacket {
    ZkgmPacket {
        salt,
        path,
        instruction: instr,
    }
}

fn success_ack(inner: &[u8]) -> Vec<u8> {
    encode_params(&Ack {
        tag: U256::from(TAG_ACK_SUCCESS),
        inner_ack: Bytes::from(inner.to_vec()),
    })
}

fn failure_ack(inner: &[u8]) -> Vec<u8> {
    encode_params(&Ack {
        tag: U256::from(TAG_ACK_FAILURE),
        inner_ack: Bytes::from(inner.to_vec()),
    })
}

fn protocol_fill_ack() -> Vec<u8> {
    encode_params(&TokenOrderAck {
        fill_type: U256::from(FILL_TYPE_PROTOCOL),
        market_maker: Bytes::new(),
    })
}

fn marketmaker_fill_ack(maker: &[u8]) -> Vec<u8> {
    encode_params(&TokenOrderAck {
        fill_type: U256::from(FILL_TYPE_MARKETMAKER),
        market_maker: Bytes::from(maker.to_vec()),
    })
}

fn batch_ack(inner_acks: Vec<Vec<u8>>) -> Vec<u8> {
    encode_params(&BatchAck {
        acknowledgements: inner_acks.into_iter().map(Bytes::from).collect(),
    })
}

fn fixed32_from_pattern(fill: u8) -> FixedBytes<32> {
    FixedBytes::from([fill; 32])
}

#[derive(Serialize)]
struct Scenario {
    /// Stable, human-readable identifier used by the gno test runner.
    name: String,
    /// Which top-level instruction opcode this scenario exercises.
    /// One of: "Call", "Batch", "Forward", "TokenOrderV1", "TokenOrderV2".
    instruction_type: String,
    /// IBC channel identifiers (informational for the gno handler test).
    source_channel: u64,
    destination_channel: u64,
    /// The ZkgmPacket envelope, decoded form.
    packet: Value,
    /// The decoded inner instruction body. Schema matches abi-fixtures field
    /// conventions: bytes → "0x..", uint256 → decimal string, etc.
    decoded: Value,
    /// Canonical `abi_encode_params(ZkgmPacket)` — the bytes carried as
    /// `packet.Data` over IBC.
    packet_data_hex: String,
    /// Canonical Ack envelope on the happy path (the inner ack varies by
    /// opcode — see per-builder commentary).
    success_ack_hex: String,
    /// Canonical Ack envelope on the universal-error failure path. This is
    /// what the gno handler emits via `universalErrorAck()` in
    /// dispatch.gno: `Ack{tag=0, inner_ack=b"UNIVERSAL_ERROR"}`.
    failure_ack_hex: String,
    /// Suggested IBC `timeout_timestamp` (nanoseconds) for a Send call that
    /// transports this packet. Encoded as a decimal string to avoid JSON
    /// number-precision loss on the uint64. Independent of the `packet` /
    /// `decoded` body — the IBC envelope's timeout is set by the relayer
    /// caller, not by ZKGM, so this field exists only as a stable input for
    /// gnokey-driven Send invocations that replay this scenario.
    tx_timeout_timestamp: String,
}

const DEFAULT_TX_TIMEOUT_NS: u64 = 1_700_000_000_000_000_000;

fn scenarios() -> Vec<Scenario> {
    let mut out = Vec::new();

    // Salt used across scenarios — distinguishable per-scenario so a swap
    // between cases is immediately visible in failure output.
    let salt_a = fixed32_from_pattern(0x11);
    let salt_b = fixed32_from_pattern(0x22);
    let salt_c = fixed32_from_pattern(0x33);
    let salt_d = fixed32_from_pattern(0x44);
    let salt_e = fixed32_from_pattern(0x55);
    let salt_zero = FixedBytes::<32>::ZERO;

    // ────────────────────────────────────────────────────────────────────
    // Call — eureka true (intent forwarded to a contract that accepts it)
    // Success-path ack inner = empty bytes (call has no payload to return).
    // ────────────────────────────────────────────────────────────────────
    {
        let call = Call {
            sender: Bytes::from(b"alice".to_vec()),
            eureka: true,
            contract_address: Bytes::from(b"bobcontract".to_vec()),
            contract_calldata: Bytes::from(vec![0xCA, 0xFE]),
        };
        let instr = instruction(INSTR_VERSION_0, OP_CALL, encode_params(&call));
        let packet = pack_zkgm(salt_a, U256::from(0u64), instr.clone());
        let packet_bytes = encode_params(&packet);
        out.push(Scenario {
            name: "recv_call_eureka_true".to_string(),
            instruction_type: "Call".to_string(),
            source_channel: 1,
            destination_channel: 2,
            packet: json!({
                "salt": hex0x(salt_a.as_slice()),
                "path": "0",
                "instruction": {
                    "version": instr.version,
                    "opcode": instr.opcode,
                    "operand": hex0x(&instr.operand),
                },
            }),
            decoded: json!({
                "sender": hex0x(b"alice"),
                "eureka": true,
                "contract_address": hex0x(b"bobcontract"),
                "contract_calldata": "0xcafe",
            }),
            packet_data_hex: hex0x(&packet_bytes),
            success_ack_hex: hex0x(&success_ack(&[])),
            failure_ack_hex: hex0x(&failure_ack(UNIVERSAL_ERROR)),
            tx_timeout_timestamp: DEFAULT_TX_TIMEOUT_NS.to_string(),
        });
    }

    // ────────────────────────────────────────────────────────────────────
    // Call — eureka false (intent rejected unless target opts in).
    // ────────────────────────────────────────────────────────────────────
    {
        let call = Call {
            sender: Bytes::from(b"alice".to_vec()),
            eureka: false,
            contract_address: Bytes::from(b"target".to_vec()),
            contract_calldata: Bytes::new(),
        };
        let instr = instruction(INSTR_VERSION_0, OP_CALL, encode_params(&call));
        let packet = pack_zkgm(salt_b, U256::from(0u64), instr.clone());
        let packet_bytes = encode_params(&packet);
        out.push(Scenario {
            name: "recv_call_eureka_false_empty_calldata".to_string(),
            instruction_type: "Call".to_string(),
            source_channel: 1,
            destination_channel: 2,
            packet: json!({
                "salt": hex0x(salt_b.as_slice()),
                "path": "0",
                "instruction": {
                    "version": instr.version,
                    "opcode": instr.opcode,
                    "operand": hex0x(&instr.operand),
                },
            }),
            decoded: json!({
                "sender": hex0x(b"alice"),
                "eureka": false,
                "contract_address": hex0x(b"target"),
                "contract_calldata": "0x",
            }),
            packet_data_hex: hex0x(&packet_bytes),
            success_ack_hex: hex0x(&success_ack(&[])),
            failure_ack_hex: hex0x(&failure_ack(UNIVERSAL_ERROR)),
            tx_timeout_timestamp: DEFAULT_TX_TIMEOUT_NS.to_string(),
        });
    }

    // ────────────────────────────────────────────────────────────────────
    // TokenOrderV2 — INITIALIZE (new wrapped voucher mint on dest chain).
    // Success-path ack inner = TokenOrderAck{FILL_TYPE_PROTOCOL}.
    // ────────────────────────────────────────────────────────────────────
    {
        let meta = TokenMetadata {
            implementation: Bytes::from(b"grc20".to_vec()),
            initializer: Bytes::from(b"init".to_vec()),
        };
        let meta_bytes = encode_params(&meta);
        let meta_hex = hex0x(&meta_bytes);
        let order = TokenOrderV2 {
            sender: Bytes::from(b"alice".to_vec()),
            receiver: Bytes::from(b"bob".to_vec()),
            base_token: Bytes::from(b"unionToken".to_vec()),
            base_amount: U256::from(100u64),
            quote_token: Bytes::from(b"uatom".to_vec()),
            quote_amount: U256::from(95u64),
            kind: TOKEN_ORDER_KIND_INITIALIZE,
            metadata: Bytes::from(meta_bytes),
        };
        let instr = instruction(INSTR_VERSION_2, OP_TOKEN_ORDER, encode_params(&order));
        let packet = pack_zkgm(salt_c, U256::from(7u64), instr.clone());
        let packet_bytes = encode_params(&packet);
        out.push(Scenario {
            name: "recv_token_order_v2_initialize_protocol_fill".to_string(),
            instruction_type: "TokenOrderV2".to_string(),
            source_channel: 1,
            destination_channel: 5,
            packet: json!({
                "salt": hex0x(salt_c.as_slice()),
                "path": "7",
                "instruction": {
                    "version": instr.version,
                    "opcode": instr.opcode,
                    "operand": hex0x(&instr.operand),
                },
            }),
            decoded: json!({
                "sender": hex0x(b"alice"),
                "receiver": hex0x(b"bob"),
                "base_token": hex0x(b"unionToken"),
                "base_amount": "100",
                "quote_token": hex0x(b"uatom"),
                "quote_amount": "95",
                "kind": TOKEN_ORDER_KIND_INITIALIZE,
                "metadata": meta_hex,
                "metadata_decoded": {
                    "implementation": hex0x(b"grc20"),
                    "initializer": hex0x(b"init"),
                },
            }),
            packet_data_hex: hex0x(&packet_bytes),
            success_ack_hex: hex0x(&success_ack(&protocol_fill_ack())),
            failure_ack_hex: hex0x(&failure_ack(UNIVERSAL_ERROR)),
            tx_timeout_timestamp: DEFAULT_TX_TIMEOUT_NS.to_string(),
        });
    }

    // ────────────────────────────────────────────────────────────────────
    // TokenOrderV2 — ESCROW (existing wrapped voucher burned, escrow on
    // source side). Empty metadata is canonical for non-initialize kinds.
    // ────────────────────────────────────────────────────────────────────
    {
        let order = TokenOrderV2 {
            sender: Bytes::from(b"alice".to_vec()),
            receiver: Bytes::from(b"bob".to_vec()),
            base_token: Bytes::from(b"ibc/v1-send".to_vec()),
            base_amount: U256::from(13u64),
            quote_token: Bytes::from(b"quote".to_vec()),
            quote_amount: U256::from(12u64),
            kind: TOKEN_ORDER_KIND_ESCROW,
            metadata: Bytes::new(),
        };
        let instr = instruction(INSTR_VERSION_2, OP_TOKEN_ORDER, encode_params(&order));
        let packet = pack_zkgm(salt_c, U256::from(0u64), instr.clone());
        let packet_bytes = encode_params(&packet);
        out.push(Scenario {
            name: "recv_token_order_v2_escrow_protocol_fill".to_string(),
            instruction_type: "TokenOrderV2".to_string(),
            source_channel: 3,
            destination_channel: 4,
            packet: json!({
                "salt": hex0x(salt_c.as_slice()),
                "path": "0",
                "instruction": {
                    "version": instr.version,
                    "opcode": instr.opcode,
                    "operand": hex0x(&instr.operand),
                },
            }),
            decoded: json!({
                "sender": hex0x(b"alice"),
                "receiver": hex0x(b"bob"),
                "base_token": hex0x(b"ibc/v1-send"),
                "base_amount": "13",
                "quote_token": hex0x(b"quote"),
                "quote_amount": "12",
                "kind": TOKEN_ORDER_KIND_ESCROW,
                "metadata": "0x",
            }),
            packet_data_hex: hex0x(&packet_bytes),
            success_ack_hex: hex0x(&success_ack(&protocol_fill_ack())),
            failure_ack_hex: hex0x(&failure_ack(UNIVERSAL_ERROR)),
            tx_timeout_timestamp: DEFAULT_TX_TIMEOUT_NS.to_string(),
        });
    }

    // ────────────────────────────────────────────────────────────────────
    // TokenOrderV2 — UNESCROW (return previously-escrowed funds on origin).
    // ────────────────────────────────────────────────────────────────────
    {
        let order = TokenOrderV2 {
            sender: Bytes::from(b"alice".to_vec()),
            receiver: Bytes::from(b"bob".to_vec()),
            base_token: Bytes::from(b"unionToken".to_vec()),
            base_amount: U256::from(500u64),
            quote_token: Bytes::from(b"uatom".to_vec()),
            quote_amount: U256::from(490u64),
            kind: TOKEN_ORDER_KIND_UNESCROW,
            metadata: Bytes::new(),
        };
        let instr = instruction(INSTR_VERSION_2, OP_TOKEN_ORDER, encode_params(&order));
        let packet = pack_zkgm(salt_d, U256::from(1u64), instr.clone());
        let packet_bytes = encode_params(&packet);
        out.push(Scenario {
            name: "recv_token_order_v2_unescrow_protocol_fill".to_string(),
            instruction_type: "TokenOrderV2".to_string(),
            source_channel: 5,
            destination_channel: 1,
            packet: json!({
                "salt": hex0x(salt_d.as_slice()),
                "path": "1",
                "instruction": {
                    "version": instr.version,
                    "opcode": instr.opcode,
                    "operand": hex0x(&instr.operand),
                },
            }),
            decoded: json!({
                "sender": hex0x(b"alice"),
                "receiver": hex0x(b"bob"),
                "base_token": hex0x(b"unionToken"),
                "base_amount": "500",
                "quote_token": hex0x(b"uatom"),
                "quote_amount": "490",
                "kind": TOKEN_ORDER_KIND_UNESCROW,
                "metadata": "0x",
            }),
            packet_data_hex: hex0x(&packet_bytes),
            success_ack_hex: hex0x(&success_ack(&protocol_fill_ack())),
            failure_ack_hex: hex0x(&failure_ack(UNIVERSAL_ERROR)),
            tx_timeout_timestamp: DEFAULT_TX_TIMEOUT_NS.to_string(),
        });
    }

    // ────────────────────────────────────────────────────────────────────
    // TokenOrderV2 — SOLVE (marketmaker fills with their own funds).
    // Success-path ack inner = TokenOrderAck{FILL_TYPE_MARKETMAKER, maker}.
    // ────────────────────────────────────────────────────────────────────
    {
        let order = TokenOrderV2 {
            sender: Bytes::from(b"alice".to_vec()),
            receiver: Bytes::from(b"bob".to_vec()),
            base_token: Bytes::from(b"unionToken".to_vec()),
            base_amount: U256::from(1_000u64),
            quote_token: Bytes::from(b"uatom".to_vec()),
            quote_amount: U256::from(980u64),
            kind: TOKEN_ORDER_KIND_SOLVE,
            metadata: Bytes::new(),
        };
        let instr = instruction(INSTR_VERSION_2, OP_TOKEN_ORDER, encode_params(&order));
        let packet = pack_zkgm(salt_e, U256::from(0u64), instr.clone());
        let packet_bytes = encode_params(&packet);
        out.push(Scenario {
            name: "recv_token_order_v2_solve_marketmaker_fill".to_string(),
            instruction_type: "TokenOrderV2".to_string(),
            source_channel: 1,
            destination_channel: 5,
            packet: json!({
                "salt": hex0x(salt_e.as_slice()),
                "path": "0",
                "instruction": {
                    "version": instr.version,
                    "opcode": instr.opcode,
                    "operand": hex0x(&instr.operand),
                },
            }),
            decoded: json!({
                "sender": hex0x(b"alice"),
                "receiver": hex0x(b"bob"),
                "base_token": hex0x(b"unionToken"),
                "base_amount": "1000",
                "quote_token": hex0x(b"uatom"),
                "quote_amount": "980",
                "kind": TOKEN_ORDER_KIND_SOLVE,
                "metadata": "0x",
            }),
            packet_data_hex: hex0x(&packet_bytes),
            success_ack_hex: hex0x(&success_ack(&marketmaker_fill_ack(b"maker-address"))),
            failure_ack_hex: hex0x(&failure_ack(UNIVERSAL_ERROR)),
            tx_timeout_timestamp: DEFAULT_TX_TIMEOUT_NS.to_string(),
        });
    }

    // ────────────────────────────────────────────────────────────────────
    // TokenOrderV1 — legacy form for backwards-compat decoders.
    // ────────────────────────────────────────────────────────────────────
    {
        let order = TokenOrderV1 {
            sender: Bytes::from(b"alice".to_vec()),
            receiver: Bytes::from(b"bob".to_vec()),
            base_token: Bytes::from(b"unionToken".to_vec()),
            base_amount: U256::from(1_000u64),
            base_token_symbol: "UNI".to_string(),
            base_token_name: "Union Token".to_string(),
            base_token_decimals: 18,
            base_token_path: U256::from(42u64),
            quote_token: Bytes::from(b"uatom".to_vec()),
            quote_amount: U256::from(2_000u64),
        };
        let instr = instruction(INSTR_VERSION_1, OP_TOKEN_ORDER, encode_params(&order));
        let packet = pack_zkgm(salt_a, U256::from(42u64), instr.clone());
        let packet_bytes = encode_params(&packet);
        out.push(Scenario {
            name: "recv_token_order_v1_legacy_protocol_fill".to_string(),
            instruction_type: "TokenOrderV1".to_string(),
            source_channel: 1,
            destination_channel: 2,
            packet: json!({
                "salt": hex0x(salt_a.as_slice()),
                "path": "42",
                "instruction": {
                    "version": instr.version,
                    "opcode": instr.opcode,
                    "operand": hex0x(&instr.operand),
                },
            }),
            decoded: json!({
                "sender": hex0x(b"alice"),
                "receiver": hex0x(b"bob"),
                "base_token": hex0x(b"unionToken"),
                "base_amount": "1000",
                "base_token_symbol": "UNI",
                "base_token_name": "Union Token",
                "base_token_decimals": 18,
                "base_token_path": "42",
                "quote_token": hex0x(b"uatom"),
                "quote_amount": "2000",
            }),
            packet_data_hex: hex0x(&packet_bytes),
            success_ack_hex: hex0x(&success_ack(&protocol_fill_ack())),
            failure_ack_hex: hex0x(&failure_ack(UNIVERSAL_ERROR)),
            tx_timeout_timestamp: DEFAULT_TX_TIMEOUT_NS.to_string(),
        });
    }

    // ────────────────────────────────────────────────────────────────────
    // Batch — empty (degenerate). Success ack = empty BatchAck.
    // ────────────────────────────────────────────────────────────────────
    {
        let batch = Batch {
            instructions: vec![],
        };
        let instr = instruction(INSTR_VERSION_0, OP_BATCH, encode_params(&batch));
        let packet = pack_zkgm(salt_zero, U256::from(0u64), instr.clone());
        let packet_bytes = encode_params(&packet);
        out.push(Scenario {
            name: "recv_batch_empty".to_string(),
            instruction_type: "Batch".to_string(),
            source_channel: 1,
            destination_channel: 2,
            packet: json!({
                "salt": hex0x(salt_zero.as_slice()),
                "path": "0",
                "instruction": {
                    "version": instr.version,
                    "opcode": instr.opcode,
                    "operand": hex0x(&instr.operand),
                },
            }),
            decoded: json!({
                "instructions": [],
            }),
            packet_data_hex: hex0x(&packet_bytes),
            success_ack_hex: hex0x(&success_ack(&batch_ack(vec![]))),
            failure_ack_hex: hex0x(&failure_ack(UNIVERSAL_ERROR)),
            tx_timeout_timestamp: DEFAULT_TX_TIMEOUT_NS.to_string(),
        });
    }

    // ────────────────────────────────────────────────────────────────────
    // Batch — mixed (a Call + a TokenOrderV2 ESCROW).
    // Success ack envelope = BatchAck of [call_ack=empty,
    // token_order_ack=protocol_fill_ack].
    // ────────────────────────────────────────────────────────────────────
    {
        let call = Call {
            sender: Bytes::from(b"sender".to_vec()),
            eureka: true,
            contract_address: Bytes::from(b"contract".to_vec()),
            contract_calldata: Bytes::from(vec![0xCA, 0xFE]),
        };
        let order = TokenOrderV2 {
            sender: Bytes::from(b"sender".to_vec()),
            receiver: Bytes::from(b"recipient".to_vec()),
            base_token: Bytes::from(b"unionToken".to_vec()),
            base_amount: U256::from(100u64),
            quote_token: Bytes::from(b"uatom".to_vec()),
            quote_amount: U256::from(95u64),
            kind: TOKEN_ORDER_KIND_ESCROW,
            metadata: Bytes::new(),
        };
        let call_instr = instruction(INSTR_VERSION_0, OP_CALL, encode_params(&call));
        let order_instr = instruction(INSTR_VERSION_2, OP_TOKEN_ORDER, encode_params(&order));
        let batch = Batch {
            instructions: vec![call_instr.clone(), order_instr.clone()],
        };
        let instr = instruction(INSTR_VERSION_0, OP_BATCH, encode_params(&batch));
        let packet = pack_zkgm(salt_a, U256::from(0u64), instr.clone());
        let packet_bytes = encode_params(&packet);
        let success_inner = batch_ack(vec![vec![], protocol_fill_ack()]);
        out.push(Scenario {
            name: "recv_batch_call_then_token_order_escrow".to_string(),
            instruction_type: "Batch".to_string(),
            source_channel: 1,
            destination_channel: 2,
            packet: json!({
                "salt": hex0x(salt_a.as_slice()),
                "path": "0",
                "instruction": {
                    "version": instr.version,
                    "opcode": instr.opcode,
                    "operand": hex0x(&instr.operand),
                },
            }),
            decoded: json!({
                "instructions": [
                    {
                        "version": call_instr.version,
                        "opcode": call_instr.opcode,
                        "operand": hex0x(&call_instr.operand),
                    },
                    {
                        "version": order_instr.version,
                        "opcode": order_instr.opcode,
                        "operand": hex0x(&order_instr.operand),
                    },
                ],
            }),
            packet_data_hex: hex0x(&packet_bytes),
            success_ack_hex: hex0x(&success_ack(&success_inner)),
            failure_ack_hex: hex0x(&failure_ack(UNIVERSAL_ERROR)),
            tx_timeout_timestamp: DEFAULT_TX_TIMEOUT_NS.to_string(),
        });
    }

    // ────────────────────────────────────────────────────────────────────
    // Forward — single hop wrapping a Call. The handler at the entry chain
    // verifies the envelope then relays the inner instruction. We capture
    // the wire shape only; per-hop side-effects are gno-side state.
    // ────────────────────────────────────────────────────────────────────
    {
        let inner_call = Call {
            sender: Bytes::from(b"sender".to_vec()),
            eureka: true,
            contract_address: Bytes::from(b"contract".to_vec()),
            contract_calldata: Bytes::from(vec![0xCA, 0xFE]),
        };
        let inner_instr = instruction(INSTR_VERSION_0, OP_CALL, encode_params(&inner_call));
        let forward = Forward {
            path: U256::from(0x12345u64),
            timeout_height: 100,
            timeout_timestamp: 1_700_000_000_000_000_000,
            instruction: inner_instr.clone(),
        };
        let instr = instruction(INSTR_VERSION_0, OP_FORWARD, encode_params(&forward));
        let packet = pack_zkgm(salt_b, U256::from(0u64), instr.clone());
        let packet_bytes = encode_params(&packet);
        out.push(Scenario {
            name: "recv_forward_single_hop_call".to_string(),
            instruction_type: "Forward".to_string(),
            source_channel: 1,
            destination_channel: 2,
            packet: json!({
                "salt": hex0x(salt_b.as_slice()),
                "path": "0",
                "instruction": {
                    "version": instr.version,
                    "opcode": instr.opcode,
                    "operand": hex0x(&instr.operand),
                },
            }),
            decoded: json!({
                "path": "74565",
                "timeout_height": 100,
                "timeout_timestamp": "1700000000000000000",
                "instruction": {
                    "version": inner_instr.version,
                    "opcode": inner_instr.opcode,
                    "operand": hex0x(&inner_instr.operand),
                },
            }),
            packet_data_hex: hex0x(&packet_bytes),
            // Forward's outer ack is a success envelope holding the inner
            // hop's ack. For a Call inner the canonical inner ack is empty.
            success_ack_hex: hex0x(&success_ack(&[])),
            failure_ack_hex: hex0x(&failure_ack(UNIVERSAL_ERROR)),
            tx_timeout_timestamp: DEFAULT_TX_TIMEOUT_NS.to_string(),
        });
    }

    // ────────────────────────────────────────────────────────────────────
    // Forward — recursive (Forward → Forward → Call). Exercises the
    // multi-hop decode path; the gno test just round-trips the envelope.
    // ────────────────────────────────────────────────────────────────────
    {
        let leaf_call = Call {
            sender: Bytes::from(b"alice".to_vec()),
            eureka: false,
            contract_address: Bytes::from(b"final-target".to_vec()),
            contract_calldata: Bytes::from(vec![0xDE, 0xAD]),
        };
        let leaf_instr = instruction(INSTR_VERSION_0, OP_CALL, encode_params(&leaf_call));
        let mid_forward = Forward {
            path: U256::from(2u64),
            timeout_height: 0,
            timeout_timestamp: 1_800_000_000_000_000_000,
            instruction: leaf_instr.clone(),
        };
        let mid_instr = instruction(INSTR_VERSION_0, OP_FORWARD, encode_params(&mid_forward));
        let outer_forward = Forward {
            path: U256::from(1u64),
            timeout_height: 0,
            timeout_timestamp: 1_800_000_000_000_000_000,
            instruction: mid_instr.clone(),
        };
        let instr = instruction(INSTR_VERSION_0, OP_FORWARD, encode_params(&outer_forward));
        let packet = pack_zkgm(salt_c, U256::from(0u64), instr.clone());
        let packet_bytes = encode_params(&packet);
        out.push(Scenario {
            name: "recv_forward_recursive_two_hops_call".to_string(),
            instruction_type: "Forward".to_string(),
            source_channel: 1,
            destination_channel: 2,
            packet: json!({
                "salt": hex0x(salt_c.as_slice()),
                "path": "0",
                "instruction": {
                    "version": instr.version,
                    "opcode": instr.opcode,
                    "operand": hex0x(&instr.operand),
                },
            }),
            decoded: json!({
                "path": "1",
                "timeout_height": 0,
                "timeout_timestamp": "1800000000000000000",
                "instruction": {
                    "version": mid_instr.version,
                    "opcode": mid_instr.opcode,
                    "operand": hex0x(&mid_instr.operand),
                },
            }),
            packet_data_hex: hex0x(&packet_bytes),
            success_ack_hex: hex0x(&success_ack(&[])),
            failure_ack_hex: hex0x(&failure_ack(UNIVERSAL_ERROR)),
            tx_timeout_timestamp: DEFAULT_TX_TIMEOUT_NS.to_string(),
        });
    }

    out
}

fn main() {
    let v = scenarios();
    let s = serde_json::to_string_pretty(&v).expect("serialize scenarios");
    println!("{}", s);
}
