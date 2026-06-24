// Package scenarios is a gno-native port of the `tools/zkgm-fixtures` Rust
// generator. It builds the same handler/dispatch end-to-end scenario fixtures
// directly with the in-tree zkgm encoders, so gno tests can consume them
// without going through the committed `scenarios.json`.
//
// Each Scenario describes a full ZkgmPacket envelope (salt, path, one of the
// four opcodes as the top-level instruction) paired with the canonical
// success/failure Ack envelope that the handler should emit on the happy path.
//
// This is wire-level ground truth; state-dependent handler effects (escrow
// balance, voucher mint, rate-limit bucket state, event emission) stay in the
// pure gno handler tests since they require gno-side state.
//
// Constants and shapes mirror union `ucs03-zkgm` `com.rs` via the zkgm package.
package fixture

import (
	u256 "gno.land/p/gnoswap/uint256"
	z "gno.land/p/onbloc/ibc/union/zkgm"
)

// universalError is the inner ack payload the fixtures pin for the failure
// path. It mirrors the Rust generator's `UNIVERSAL_ERROR` byte string.
var universalError = []byte("UNIVERSAL_ERROR")

// defaultTxTimeoutNS is the suggested IBC timeout_timestamp (nanoseconds) for a
// Send call that transports a scenario packet. Independent of the packet body.
const defaultTxTimeoutNS uint64 = 1_700_000_000_000_000_000

// Scenario is the gno-native equivalent of the Rust `Scenario` record. Unlike
// the JSON form it carries the decoded packet plus the raw encoded bytes, so a
// test can either re-encode `Packet` and assert byte-equality with `PacketData`
// or decode `PacketData` and assert structural equality with `Packet`.
type Scenario struct {
	// Name is a stable, human-readable identifier used in test failure output.
	Name string
	// InstructionType is the top-level opcode this scenario exercises:
	// "Call", "Batch", "Forward", "TokenOrderV1", or "TokenOrderV2".
	InstructionType string
	// SourceChannel / DestinationChannel are informational IBC channel ids.
	SourceChannel      uint64
	DestinationChannel uint64
	// Packet is the decoded ZkgmPacket envelope.
	Packet z.ZkgmPacket
	// PacketData is canonical EncodeZkgmPacket(Packet) — the bytes carried as
	// packet.Data over IBC.
	PacketData []byte
	// SuccessAck is the canonical Ack envelope on the happy path (the inner ack
	// varies by opcode).
	SuccessAck []byte
	// FailureAck is the canonical Ack envelope on the universal-error failure
	// path: Ack{tag=0, inner_ack="UNIVERSAL_ERROR"}.
	FailureAck []byte
	// TxTimeoutTimestamp is a suggested IBC timeout (ns) for gnokey-driven Send
	// replays. Independent of the packet body.
	TxTimeoutTimestamp uint64
}

// ───────────────────────────────────────────────────────────────────────
// Helpers (port of the Rust generator's free functions)
// ───────────────────────────────────────────────────────────────────────

func must(b []byte, err error) []byte {
	if err != nil {
		panic(err)
	}
	return b
}

// makeScenario fills the fields that are identical across every scenario
// (encoded packet bytes, the universal-error failure ack, the default tx
// timeout) so each builder block only has to spell out what actually differs:
// the name, opcode, channels, packet, and the inner success-ack payload.
func makeScenario(name, instrType string, srcCh, dstCh uint64, packet z.ZkgmPacket, successInner []byte) Scenario {
	return Scenario{
		Name:               name,
		InstructionType:    instrType,
		SourceChannel:      srcCh,
		DestinationChannel: dstCh,
		Packet:             packet,
		PacketData:         must(z.EncodeZkgmPacket(packet)),
		SuccessAck:         successAck(successInner),
		FailureAck:         failureAck(universalError),
		TxTimeoutTimestamp: defaultTxTimeoutNS,
	}
}

func instruction(version, opcode uint8, operand []byte) z.Instruction {
	return z.Instruction{Version: version, Opcode: opcode, Operand: operand}
}

func packZkgm(salt [32]byte, path uint64, instr z.Instruction) z.ZkgmPacket {
	return z.ZkgmPacket{Salt: salt, Path: u256.NewUint(path), Instruction: instr}
}

func successAck(inner []byte) []byte {
	return must(z.EncodeAck(z.Ack{
		Tag:      z.Uint256FromBytes32(z.TAG_ACK_SUCCESS),
		InnerAck: inner,
	}))
}

func failureAck(inner []byte) []byte {
	return must(z.EncodeAck(z.Ack{
		Tag:      z.Uint256FromBytes32(z.TAG_ACK_FAILURE),
		InnerAck: inner,
	}))
}

func protocolFillAck() []byte {
	return must(z.EncodeTokenOrderAck(z.TokenOrderAck{
		FillType:    z.Uint256FromBytes32(z.FILL_TYPE_PROTOCOL),
		MarketMaker: nil,
	}))
}

func marketmakerFillAck(maker []byte) []byte {
	return must(z.EncodeTokenOrderAck(z.TokenOrderAck{
		FillType:    z.Uint256FromBytes32(z.FILL_TYPE_MARKETMAKER),
		MarketMaker: maker,
	}))
}

func batchAck(innerAcks [][]byte) []byte {
	return must(z.EncodeBatchAck(z.BatchAck{Acknowledgements: innerAcks}))
}

// fixed32 returns a 32-byte array filled with the given byte, matching the Rust
// generator's per-scenario distinguishable salts.
func fixed32(fill byte) [32]byte {
	var b [32]byte
	for i := range b {
		b[i] = fill
	}
	return b
}

// ───────────────────────────────────────────────────────────────────────
// Scenario builders
// ───────────────────────────────────────────────────────────────────────

// All returns every scenario in the same order as the Rust generator.
func All() []Scenario {
	saltA := fixed32(0x11)
	saltB := fixed32(0x22)
	saltC := fixed32(0x33)
	saltD := fixed32(0x44)
	saltE := fixed32(0x55)
	var saltZero [32]byte

	out := make([]Scenario, 0, 11)

	// Call — eureka true (intent forwarded to a contract that accepts it).
	// Success-path ack inner = empty bytes.
	{
		call := z.Call{
			Sender:           []byte("alice"),
			Eureka:           true,
			ContractAddress:  []byte("bobcontract"),
			ContractCalldata: []byte{0xCA, 0xFE},
		}
		instr := instruction(z.INSTR_VERSION_0, z.OP_CALL, must(z.EncodeCall(call)))
		packet := packZkgm(saltA, 0, instr)
		out = append(out, makeScenario("recv_call_eureka_true", "Call", 1, 2, packet, []byte{}))
	}

	// Call — eureka false (intent rejected unless target opts in).
	{
		call := z.Call{
			Sender:           []byte("alice"),
			Eureka:           false,
			ContractAddress:  []byte("target"),
			ContractCalldata: []byte{},
		}
		instr := instruction(z.INSTR_VERSION_0, z.OP_CALL, must(z.EncodeCall(call)))
		packet := packZkgm(saltB, 0, instr)
		out = append(out, makeScenario("recv_call_eureka_false_empty_calldata", "Call", 1, 2, packet, []byte{}))
	}

	// TokenOrderV2 — INITIALIZE (new wrapped voucher mint on dest chain).
	// Success-path ack inner = TokenOrderAck{FILL_TYPE_PROTOCOL}.
	{
		meta := z.TokenMetadata{
			Implementation: []byte("grc20"),
			Initializer:    []byte("init"),
		}
		order := z.TokenOrderV2{
			Sender:      []byte("alice"),
			Receiver:    []byte("bob"),
			BaseToken:   []byte("unionToken"),
			BaseAmount:  u256.NewUint(100),
			QuoteToken:  []byte("uatom"),
			QuoteAmount: u256.NewUint(95),
			Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
			Metadata:    must(z.EncodeTokenMetadata(meta)),
		}
		instr := instruction(z.INSTR_VERSION_2, z.OP_TOKEN_ORDER, must(z.EncodeTokenOrderV2(order)))
		packet := packZkgm(saltC, 7, instr)
		out = append(out, makeScenario("recv_token_order_v2_initialize_protocol_fill", "TokenOrderV2", 1, 5, packet, protocolFillAck()))
	}

	// TokenOrderV2 — ESCROW (existing wrapped voucher burned, escrow on source
	// side). Empty metadata is canonical for non-initialize kinds.
	{
		order := z.TokenOrderV2{
			Sender:      []byte("alice"),
			Receiver:    []byte("bob"),
			BaseToken:   []byte("ibc/v1-send"),
			BaseAmount:  u256.NewUint(13),
			QuoteToken:  []byte("quote"),
			QuoteAmount: u256.NewUint(12),
			Kind:        z.TOKEN_ORDER_KIND_ESCROW,
			Metadata:    []byte{},
		}
		instr := instruction(z.INSTR_VERSION_2, z.OP_TOKEN_ORDER, must(z.EncodeTokenOrderV2(order)))
		packet := packZkgm(saltC, 0, instr)
		out = append(out, makeScenario("recv_token_order_v2_escrow_protocol_fill", "TokenOrderV2", 3, 4, packet, protocolFillAck()))
	}

	// TokenOrderV2 — UNESCROW (return previously-escrowed funds on origin).
	{
		order := z.TokenOrderV2{
			Sender:      []byte("alice"),
			Receiver:    []byte("bob"),
			BaseToken:   []byte("unionToken"),
			BaseAmount:  u256.NewUint(500),
			QuoteToken:  []byte("uatom"),
			QuoteAmount: u256.NewUint(490),
			Kind:        z.TOKEN_ORDER_KIND_UNESCROW,
			Metadata:    []byte{},
		}
		instr := instruction(z.INSTR_VERSION_2, z.OP_TOKEN_ORDER, must(z.EncodeTokenOrderV2(order)))
		packet := packZkgm(saltD, 1, instr)
		out = append(out, makeScenario("recv_token_order_v2_unescrow_protocol_fill", "TokenOrderV2", 5, 1, packet, protocolFillAck()))
	}

	// TokenOrderV2 — SOLVE (marketmaker fills with their own funds).
	// Success-path ack inner = TokenOrderAck{FILL_TYPE_MARKETMAKER, maker}.
	{
		order := z.TokenOrderV2{
			Sender:      []byte("alice"),
			Receiver:    []byte("bob"),
			BaseToken:   []byte("unionToken"),
			BaseAmount:  u256.NewUint(1_000),
			QuoteToken:  []byte("uatom"),
			QuoteAmount: u256.NewUint(980),
			Kind:        z.TOKEN_ORDER_KIND_SOLVE,
			Metadata:    []byte{},
		}
		instr := instruction(z.INSTR_VERSION_2, z.OP_TOKEN_ORDER, must(z.EncodeTokenOrderV2(order)))
		packet := packZkgm(saltE, 0, instr)
		out = append(out, makeScenario("recv_token_order_v2_solve_marketmaker_fill", "TokenOrderV2", 1, 5, packet, marketmakerFillAck([]byte("maker-address"))))
	}

	// TokenOrderV1 — legacy form for backwards-compat decoders.
	{
		order := z.TokenOrderV1{
			Sender:            []byte("alice"),
			Receiver:          []byte("bob"),
			BaseToken:         []byte("unionToken"),
			BaseAmount:        u256.NewUint(1_000),
			BaseTokenSymbol:   "UNI",
			BaseTokenName:     "Union Token",
			BaseTokenDecimals: 18,
			BaseTokenPath:     u256.NewUint(42),
			QuoteToken:        []byte("uatom"),
			QuoteAmount:       u256.NewUint(2_000),
		}
		instr := instruction(z.INSTR_VERSION_1, z.OP_TOKEN_ORDER, must(z.EncodeTokenOrderV1(order)))
		packet := packZkgm(saltA, 42, instr)
		out = append(out, makeScenario("recv_token_order_v1_legacy_protocol_fill", "TokenOrderV1", 1, 2, packet, protocolFillAck()))
	}

	// Batch — empty (degenerate). Success ack = empty BatchAck.
	{
		instr := instruction(z.INSTR_VERSION_0, z.OP_BATCH, must(z.EncodeBatch(z.Batch{Instructions: nil})))
		packet := packZkgm(saltZero, 0, instr)
		out = append(out, makeScenario("recv_batch_empty", "Batch", 1, 2, packet, batchAck(nil)))
	}

	// Batch — mixed (a Call + a TokenOrderV2 ESCROW). Success ack envelope =
	// BatchAck of [call_ack=empty, token_order_ack=protocol_fill_ack].
	{
		call := z.Call{
			Sender:           []byte("sender"),
			Eureka:           true,
			ContractAddress:  []byte("contract"),
			ContractCalldata: []byte{0xCA, 0xFE},
		}
		order := z.TokenOrderV2{
			Sender:      []byte("sender"),
			Receiver:    []byte("recipient"),
			BaseToken:   []byte("unionToken"),
			BaseAmount:  u256.NewUint(100),
			QuoteToken:  []byte("uatom"),
			QuoteAmount: u256.NewUint(95),
			Kind:        z.TOKEN_ORDER_KIND_ESCROW,
			Metadata:    []byte{},
		}
		callInstr := instruction(z.INSTR_VERSION_0, z.OP_CALL, must(z.EncodeCall(call)))
		orderInstr := instruction(z.INSTR_VERSION_2, z.OP_TOKEN_ORDER, must(z.EncodeTokenOrderV2(order)))
		batch := z.Batch{Instructions: []z.Instruction{callInstr, orderInstr}}
		instr := instruction(z.INSTR_VERSION_0, z.OP_BATCH, must(z.EncodeBatch(batch)))
		packet := packZkgm(saltA, 0, instr)
		successInner := batchAck([][]byte{{}, protocolFillAck()})
		out = append(out, makeScenario("recv_batch_call_then_token_order_escrow", "Batch", 1, 2, packet, successInner))
	}

	// Forward — single hop wrapping a Call. We capture the wire shape only;
	// per-hop side-effects are gno-side state.
	{
		innerCall := z.Call{
			Sender:           []byte("sender"),
			Eureka:           true,
			ContractAddress:  []byte("contract"),
			ContractCalldata: []byte{0xCA, 0xFE},
		}
		innerInstr := instruction(z.INSTR_VERSION_0, z.OP_CALL, must(z.EncodeCall(innerCall)))
		forward := z.Forward{
			Path:             u256.NewUint(0x12345),
			TimeoutHeight:    100,
			TimeoutTimestamp: 1_700_000_000_000_000_000,
			Instruction:      innerInstr,
		}
		instr := instruction(z.INSTR_VERSION_0, z.OP_FORWARD, must(z.EncodeForward(forward)))
		packet := packZkgm(saltB, 0, instr)
		// Forward's outer ack holds the inner hop's ack; for a Call inner the
		// canonical inner ack is empty.
		out = append(out, makeScenario("recv_forward_single_hop_call", "Forward", 1, 2, packet, []byte{}))
	}

	// Forward — recursive (Forward → Forward → Call). Exercises the multi-hop
	// decode path; the test just round-trips the envelope.
	{
		leafCall := z.Call{
			Sender:           []byte("alice"),
			Eureka:           false,
			ContractAddress:  []byte("final-target"),
			ContractCalldata: []byte{0xDE, 0xAD},
		}
		leafInstr := instruction(z.INSTR_VERSION_0, z.OP_CALL, must(z.EncodeCall(leafCall)))
		midForward := z.Forward{
			Path:             u256.NewUint(2),
			TimeoutHeight:    0,
			TimeoutTimestamp: 1_800_000_000_000_000_000,
			Instruction:      leafInstr,
		}
		midInstr := instruction(z.INSTR_VERSION_0, z.OP_FORWARD, must(z.EncodeForward(midForward)))
		outerForward := z.Forward{
			Path:             u256.NewUint(1),
			TimeoutHeight:    0,
			TimeoutTimestamp: 1_800_000_000_000_000_000,
			Instruction:      midInstr,
		}
		instr := instruction(z.INSTR_VERSION_0, z.OP_FORWARD, must(z.EncodeForward(outerForward)))
		packet := packZkgm(saltC, 0, instr)
		out = append(out, makeScenario("recv_forward_recursive_two_hops_call", "Forward", 1, 2, packet, []byte{}))
	}

	return out
}

// ByName returns the scenario with the given name and whether it was found.
func ByName(name string) (Scenario, bool) {
	for _, s := range All() {
		if s.Name == name {
			return s, true
		}
	}
	return Scenario{}, false
}
