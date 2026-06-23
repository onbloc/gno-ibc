package zkgm

import (
	"testing"

	u256 "gno.land/p/gnoswap/uint256"
)

func TestZkgmPacketType(t *testing.T) {
	tests := []struct {
		name   string
		packet ZkgmPacket
	}{
		{
			"packet fields",
			ZkgmPacket{
				Salt: mustSalt(0xAB),
				Path: u256.NewUint(7),
				Instruction: Instruction{
					Version: INSTR_VERSION_0,
					Opcode:  OP_CALL,
					Operand: []byte{0x01, 0x02},
				},
			},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assertUint64(t, "packet path", tt.packet.Path, 7)
			if tt.packet.Salt[0] != 0xAB || tt.packet.Instruction.Opcode != OP_CALL || len(tt.packet.Instruction.Operand) != 2 {
				t.Fatalf("unexpected packet fields: %#v", tt.packet)
			}
		})
	}
}

func TestInstructionContainerTypes(t *testing.T) {
	tests := []struct {
		name    string
		forward Forward
		call    Call
		batch   Batch
	}{
		{
			"container fields",
			Forward{
				Path:             u256.NewUint(11),
				TimeoutHeight:    12,
				TimeoutTimestamp: 13,
				Instruction: Instruction{
					Version: INSTR_VERSION_1,
					Opcode:  OP_BATCH,
					Operand: []byte{0xAA},
				},
			},
			Call{
				Sender:           []byte("sender"),
				Eureka:           true,
				ContractAddress:  []byte("contract"),
				ContractCalldata: []byte{0xCA, 0x11},
			},
			Batch{
				Instructions: []Instruction{
					{
						Version: INSTR_VERSION_1,
						Opcode:  OP_BATCH,
						Operand: []byte{0xAA},
					},
				},
			},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assertUint64(t, "forward path", tt.forward.Path, 11)
			if tt.forward.TimeoutHeight != 12 || tt.forward.TimeoutTimestamp != 13 {
				t.Fatalf("unexpected forward timeout fields: %#v", tt.forward)
			}
			if !tt.call.Eureka || string(tt.call.Sender) != "sender" || string(tt.call.ContractAddress) != "contract" {
				t.Fatalf("unexpected call fields: %#v", tt.call)
			}
			if len(tt.batch.Instructions) != 1 || tt.batch.Instructions[0].Opcode != OP_BATCH {
				t.Fatalf("unexpected batch fields: %#v", tt.batch)
			}
		})
	}
}

func TestTokenOrderTypes(t *testing.T) {
	tests := []struct {
		name string
		v1   TokenOrderV1
		v2   TokenOrderV2
	}{
		{
			"token order fields",
			TokenOrderV1{
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
			},
			TokenOrderV2{
				Sender:      []byte("alice"),
				Receiver:    []byte("bob"),
				BaseToken:   []byte("base"),
				BaseAmount:  u256.NewUint(100),
				QuoteToken:  []byte("quote"),
				QuoteAmount: u256.NewUint(200),
				Kind:        TOKEN_ORDER_KIND_ESCROW,
				Metadata:    []byte{0x01},
			},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assertUint64(t, "v1 base amount", tt.v1.BaseAmount, 100)
			assertUint64(t, "v1 base token path", tt.v1.BaseTokenPath, 42)
			assertUint64(t, "v1 quote amount", tt.v1.QuoteAmount, 200)
			assertUint64(t, "v2 base amount", tt.v2.BaseAmount, 100)
			assertUint64(t, "v2 quote amount", tt.v2.QuoteAmount, 200)
			if tt.v1.BaseTokenSymbol != "BASE" || tt.v1.BaseTokenDecimals != 6 || tt.v2.Kind != TOKEN_ORDER_KIND_ESCROW {
				t.Fatalf("unexpected token order fields: %#v %#v", tt.v1, tt.v2)
			}
		})
	}
}

func TestMetadataAndAckTypes(t *testing.T) {
	wantFillType := new(u256.Uint).SetBytes(FILL_TYPE_PROTOCOL[:])
	tests := []struct {
		name           string
		tokenMetadata  TokenMetadata
		solverMetadata SolverMetadata
		ack            Ack
		batchAck       BatchAck
		tokenOrderAck  TokenOrderAck
	}{
		{
			"metadata and ack fields",
			TokenMetadata{
				Implementation: []byte("impl"),
				Initializer:    []byte("init"),
			},
			SolverMetadata{
				SolverAddress: []byte("solver"),
				Metadata:      []byte("meta"),
			},
			Ack{
				Tag:      u256.NewUint(1),
				InnerAck: []byte{0xAC, 0x0B},
			},
			BatchAck{
				Acknowledgements: [][]byte{{0x01}, {0x02, 0x03}},
			},
			TokenOrderAck{
				FillType:    wantFillType,
				MarketMaker: []byte("maker"),
			},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if string(tt.tokenMetadata.Implementation) != "impl" || string(tt.tokenMetadata.Initializer) != "init" {
				t.Fatalf("unexpected token metadata fields: %#v", tt.tokenMetadata)
			}
			if string(tt.solverMetadata.SolverAddress) != "solver" || string(tt.solverMetadata.Metadata) != "meta" {
				t.Fatalf("unexpected solver metadata fields: %#v", tt.solverMetadata)
			}
			assertUint64(t, "ack tag", tt.ack.Tag, 1)
			if len(tt.ack.InnerAck) != 2 || len(tt.batchAck.Acknowledgements) != 2 || len(tt.batchAck.Acknowledgements[1]) != 2 {
				t.Fatalf("unexpected ack fields: %#v %#v", tt.ack, tt.batchAck)
			}
			if tt.tokenOrderAck.FillType.Cmp(wantFillType) != 0 ||
				string(tt.tokenOrderAck.MarketMaker) != "maker" {
				t.Fatalf("unexpected token order ack fields: %#v", tt.tokenOrderAck)
			}
		})
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
