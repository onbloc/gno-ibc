package zkgm

import (
	"testing"

	u256 "gno.land/p/gnoswap/uint256"
)

func TestZkgmPacketType(t *testing.T) {
	packet := ZkgmPacket{
		Salt: mustSalt(0xAB),
		Path: u256.NewUint(7),
		Instruction: Instruction{
			Version: INSTR_VERSION_0,
			Opcode:  OP_CALL,
			Operand: []byte{0x01, 0x02},
		},
	}

	assertUint64(t, "packet path", packet.Path, 7)
	if packet.Salt[0] != 0xAB || packet.Instruction.Opcode != OP_CALL || len(packet.Instruction.Operand) != 2 {
		t.Fatalf("unexpected packet fields: %#v", packet)
	}
}

func TestInstructionContainerTypes(t *testing.T) {
	forward := Forward{
		Path:             u256.NewUint(11),
		TimeoutHeight:    12,
		TimeoutTimestamp: 13,
		Instruction: Instruction{
			Version: INSTR_VERSION_1,
			Opcode:  OP_BATCH,
			Operand: []byte{0xAA},
		},
	}
	call := Call{
		Sender:           []byte("sender"),
		Eureka:           true,
		ContractAddress:  []byte("contract"),
		ContractCalldata: []byte{0xCA, 0x11},
	}
	batch := Batch{
		Instructions: []Instruction{forward.Instruction},
	}

	assertUint64(t, "forward path", forward.Path, 11)
	if forward.TimeoutHeight != 12 || forward.TimeoutTimestamp != 13 {
		t.Fatalf("unexpected forward timeout fields: %#v", forward)
	}
	if !call.Eureka || string(call.Sender) != "sender" || string(call.ContractAddress) != "contract" {
		t.Fatalf("unexpected call fields: %#v", call)
	}
	if len(batch.Instructions) != 1 || batch.Instructions[0].Opcode != OP_BATCH {
		t.Fatalf("unexpected batch fields: %#v", batch)
	}
}

func TestTokenOrderTypes(t *testing.T) {
	v1 := TokenOrderV1{
		Sender:            []byte("alice"),
		Receiver:          []byte("bob"),
		BaseToken:         []byte("base"),
		BaseAmount:        u256.NewUint(100),
		BaseTokenSymbol:   "BASE",
		BaseTokenName:     "Base Token",
		BaseTokenDecimals: 6,
		BaseTokenPath:     u256.NewUint(42),
		QuoteToken:        []byte("quote"),
		QuoteAmount:       u256.NewUint(200),
	}
	v2 := TokenOrderV2{
		Sender:      []byte("alice"),
		Receiver:    []byte("bob"),
		BaseToken:   []byte("base"),
		BaseAmount:  u256.NewUint(100),
		QuoteToken:  []byte("quote"),
		QuoteAmount: u256.NewUint(200),
		Kind:        TOKEN_ORDER_KIND_ESCROW,
		Metadata:    []byte{0x01},
	}

	assertUint64(t, "v1 base amount", v1.BaseAmount, 100)
	assertUint64(t, "v1 base token path", v1.BaseTokenPath, 42)
	assertUint64(t, "v1 quote amount", v1.QuoteAmount, 200)
	assertUint64(t, "v2 base amount", v2.BaseAmount, 100)
	assertUint64(t, "v2 quote amount", v2.QuoteAmount, 200)
	if v1.BaseTokenSymbol != "BASE" || v1.BaseTokenDecimals != 6 || v2.Kind != TOKEN_ORDER_KIND_ESCROW {
		t.Fatalf("unexpected token order fields: %#v %#v", v1, v2)
	}
}

func TestMetadataAndAckTypes(t *testing.T) {
	tokenMetadata := TokenMetadata{
		Implementation: []byte("impl"),
		Initializer:    []byte("init"),
	}
	solverMetadata := SolverMetadata{
		SolverAddress: []byte("solver"),
		Metadata:      []byte("meta"),
	}
	ack := Ack{
		Tag:      u256.NewUint(1),
		InnerAck: []byte{0xAC, 0x0B},
	}
	batchAck := BatchAck{
		Acknowledgements: [][]byte{{0x01}, {0x02, 0x03}},
	}
	wantFillType := new(u256.Uint).SetBytes(FILL_TYPE_PROTOCOL[:])
	tokenOrderAck := TokenOrderAck{
		FillType:    wantFillType,
		MarketMaker: []byte("maker"),
	}

	if string(tokenMetadata.Implementation) != "impl" || string(tokenMetadata.Initializer) != "init" {
		t.Fatalf("unexpected token metadata fields: %#v", tokenMetadata)
	}
	if string(solverMetadata.SolverAddress) != "solver" || string(solverMetadata.Metadata) != "meta" {
		t.Fatalf("unexpected solver metadata fields: %#v", solverMetadata)
	}
	assertUint64(t, "ack tag", ack.Tag, 1)
	if len(ack.InnerAck) != 2 || len(batchAck.Acknowledgements) != 2 || len(batchAck.Acknowledgements[1]) != 2 {
		t.Fatalf("unexpected ack fields: %#v %#v", ack, batchAck)
	}
	if tokenOrderAck.FillType.Cmp(wantFillType) != 0 ||
		string(tokenOrderAck.MarketMaker) != "maker" {
		t.Fatalf("unexpected token order ack fields: %#v", tokenOrderAck)
	}
}

func mustSalt(fill byte) [32]byte {
	var salt [32]byte
	for i := range salt {
		salt[i] = fill
	}
	return salt
}

func assertUint64(t *testing.T, name string, got *u256.Uint, want uint64) {
	t.Helper()

	wantUint := u256.NewUint(want)
	if got.Cmp(wantUint) != 0 {
		t.Fatalf("%s: got %s want %s", name, got.ToString(), wantUint.ToString())
	}
}
