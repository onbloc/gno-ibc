package fixture

import (
	"bytes"
	"testing"

	u256 "gno.land/p/gnoswap/uint256"
	z "gno.land/p/onbloc/ibc/union/zkgm"
)

// These tests double as usage examples: each one assembles the exact packet /
// ack it wants from the toolkit, then verifies by decoding it back. There are no
// pre-baked scenario values — a real handler/dispatch test does the same.

// TestCallScenarioRoundTrips builds a Call packet, encodes it, decodes it back,
// and asserts the inner Call survives the round trip.
func TestCallScenarioRoundTrips(t *testing.T) {
	call := z.Call{
		Sender:           []byte("alice"),
		Eureka:           true,
		ContractAddress:  []byte("bobcontract"),
		ContractCalldata: []byte{0xCA, 0xFE},
	}
	instr := Instruction(z.INSTR_VERSION_0, z.OP_CALL, Must(z.EncodeCall(call)))
	packet := Packet(Fixed32(0x11), 0, instr)

	decoded, err := z.DecodeZkgmPacket(EncodePacket(packet))
	if err != nil {
		t.Fatalf("decode packet: %v", err)
	}
	if decoded.Instruction.Opcode != z.OP_CALL {
		t.Fatalf("opcode: got %d, want %d", decoded.Instruction.Opcode, z.OP_CALL)
	}

	gotCall, err := z.DecodeCall(decoded.Instruction.Operand)
	if err != nil {
		t.Fatalf("decode call: %v", err)
	}
	if !bytes.Equal(gotCall.Sender, call.Sender) || gotCall.Eureka != call.Eureka ||
		!bytes.Equal(gotCall.ContractAddress, call.ContractAddress) ||
		!bytes.Equal(gotCall.ContractCalldata, call.ContractCalldata) {
		t.Fatalf("call round-trip mismatch: got %+v", gotCall)
	}
}

// TestSuccessAndFailureAck verifies the Success/Failure envelope tags and inner
// payloads decode back to what was put in.
func TestSuccessAndFailureAck(t *testing.T) {
	success, err := z.DecodeAck(SuccessAck([]byte{}))
	if err != nil {
		t.Fatalf("decode success ack: %v", err)
	}
	if !success.Tag.Eq(z.Uint256FromBytes32(z.TAG_ACK_SUCCESS)) {
		t.Fatalf("success tag: got %s", success.Tag.ToString())
	}

	failure, err := z.DecodeAck(FailureAck([]byte("UNIVERSAL_ERROR")))
	if err != nil {
		t.Fatalf("decode failure ack: %v", err)
	}
	if !failure.Tag.Eq(z.Uint256FromBytes32(z.TAG_ACK_FAILURE)) {
		t.Fatalf("failure tag: got %s", failure.Tag.ToString())
	}
	if string(failure.InnerAck) != "UNIVERSAL_ERROR" {
		t.Fatalf("failure inner: got %q", string(failure.InnerAck))
	}
}

// TestTokenOrderFillAcks verifies the protocol- and marketmaker-fill inner acks
// carry the right fill type and market maker.
func TestTokenOrderFillAcks(t *testing.T) {
	protocol, err := z.DecodeTokenOrderAck(ProtocolFillAck())
	if err != nil {
		t.Fatalf("decode protocol fill ack: %v", err)
	}
	if !protocol.FillType.Eq(z.Uint256FromBytes32(z.FILL_TYPE_PROTOCOL)) {
		t.Fatalf("protocol fill type: got %s", protocol.FillType.ToString())
	}

	maker, err := z.DecodeTokenOrderAck(MarketMakerFillAck([]byte("maker-address")))
	if err != nil {
		t.Fatalf("decode marketmaker fill ack: %v", err)
	}
	if !maker.FillType.Eq(z.Uint256FromBytes32(z.FILL_TYPE_MARKETMAKER)) {
		t.Fatalf("marketmaker fill type: got %s", maker.FillType.ToString())
	}
	if string(maker.MarketMaker) != "maker-address" {
		t.Fatalf("marketmaker: got %q", string(maker.MarketMaker))
	}
}

// TestBatchScenario builds a 2-instruction batch packet and its matching
// BatchAck, then decodes both back.
func TestBatchScenario(t *testing.T) {
	callInstr := Instruction(z.INSTR_VERSION_0, z.OP_CALL, Must(z.EncodeCall(z.Call{
		Sender:          []byte("sender"),
		ContractAddress: []byte("contract"),
	})))
	orderInstr := Instruction(z.INSTR_VERSION_2, z.OP_TOKEN_ORDER, Must(z.EncodeTokenOrderV2(z.TokenOrderV2{
		Sender:      []byte("sender"),
		Receiver:    []byte("recipient"),
		BaseToken:   []byte("unionToken"),
		BaseAmount:  u256.NewUint(100),
		QuoteToken:  []byte("uatom"),
		QuoteAmount: u256.NewUint(95),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	})))
	batchInstr := Instruction(z.INSTR_VERSION_0, z.OP_BATCH, Must(z.EncodeBatch(z.Batch{
		Instructions: []z.Instruction{callInstr, orderInstr},
	})))
	packet := Packet(Fixed32(0x22), 0, batchInstr)

	decoded, err := z.DecodeZkgmPacket(EncodePacket(packet))
	if err != nil {
		t.Fatalf("decode packet: %v", err)
	}
	batch, err := z.DecodeBatch(decoded.Instruction.Operand)
	if err != nil {
		t.Fatalf("decode batch: %v", err)
	}
	if len(batch.Instructions) != 2 {
		t.Fatalf("batch instructions: got %d, want 2", len(batch.Instructions))
	}

	ack, err := z.DecodeBatchAck(BatchAck([][]byte{{}, ProtocolFillAck()}))
	if err != nil {
		t.Fatalf("decode batch ack: %v", err)
	}
	if len(ack.Acknowledgements) != 2 {
		t.Fatalf("batch ack entries: got %d, want 2", len(ack.Acknowledgements))
	}
}
