// Test vectors and cases are based on the following references:
//
//	https://github.com/unionlabs/union/blob/main/lib/ucs03-zkgm-packet/src/lib.rs
package zkgm

import (
	"bytes"
	"encoding/hex"
	"strconv"
	"testing"

	"gno.land/p/onbloc/encoding/abi"
	"gno.land/p/onbloc/json"

	u256 "gno.land/p/gnoswap/uint256"
)

func TestUnionRealWorldDecoding(t *testing.T) {
	tests := []struct {
		name       string
		packetHex  string
		ackHex     string
		wantSender string
	}{
		{
			"union batch packet with token order and call ack",
			"79176e1d5f2779e14b2f5f885bfe7b35e78802643522ce0dad5cac4e4a44271f" +
				"0000000000000000000000000000000000000000000000000000000000000000" +
				"0000000000000000000000000000000000000000000000000000000000000060" +
				"0000000000000000000000000000000000000000000000000000000000000000" +
				"0000000000000000000000000000000000000000000000000000000000000002" +
				"0000000000000000000000000000000000000000000000000000000000000060" +
				"0000000000000000000000000000000000000000000000000000000000000660" +
				"0000000000000000000000000000000000000000000000000000000000000020" +
				"0000000000000000000000000000000000000000000000000000000000000002" +
				"0000000000000000000000000000000000000000000000000000000000000040" +
				"00000000000000000000000000000000000000000000000000000000000003a0" +
				"0000000000000000000000000000000000000000000000000000000000000001" +
				"0000000000000000000000000000000000000000000000000000000000000003" +
				"0000000000000000000000000000000000000000000000000000000000000060" +
				"00000000000000000000000000000000000000000000000000000000000002e0" +
				"0000000000000000000000000000000000000000000000000000000000000140" +
				"0000000000000000000000000000000000000000000000000000000000000180" +
				"00000000000000000000000000000000000000000000000000000000000001e0" +
				"0000000000000000000000000000000000000000000000000000000000002710" +
				"0000000000000000000000000000000000000000000000000000000000000220" +
				"0000000000000000000000000000000000000000000000000000000000000260" +
				"0000000000000000000000000000000000000000000000000000000000000006" +
				"0000000000000000000000000000000000000000000000000000000000000001" +
				"00000000000000000000000000000000000000000000000000000000000002a0" +
				"0000000000000000000000000000000000000000000000000000000000002710" +
				"0000000000000000000000000000000000000000000000000000000000000014" +
				"15ee7c367f4232241028c36e720803100757c6e9000000000000000000000000" +
				"000000000000000000000000000000000000000000000000000000000000003e" +
				"62626e316d377a72356a77346b397a32327239616a676766347563616c777937" +
				"7578767539676b7736746e736d7634326c766a706b7761736167656b35670000" +
				"0000000000000000000000000000000000000000000000000000000000000014" +
				"e53dcec07d16d88e386ae0710e86d9a400f83c31000000000000000000000000" +
				"0000000000000000000000000000000000000000000000000000000000000004" +
				"4241425900000000000000000000000000000000000000000000000000000000" +
				"0000000000000000000000000000000000000000000000000000000000000007" +
				"426162796c6f6e00000000000000000000000000000000000000000000000000" +
				"0000000000000000000000000000000000000000000000000000000000000004" +
				"7562626e00000000000000000000000000000000000000000000000000000000" +
				"0000000000000000000000000000000000000000000000000000000000000000" +
				"0000000000000000000000000000000000000000000000000000000000000001" +
				"0000000000000000000000000000000000000000000000000000000000000060" +
				"0000000000000000000000000000000000000000000000000000000000000200" +
				"0000000000000000000000000000000000000000000000000000000000000080" +
				"0000000000000000000000000000000000000000000000000000000000000000" +
				"00000000000000000000000000000000000000000000000000000000000000c0" +
				"0000000000000000000000000000000000000000000000000000000000000120" +
				"0000000000000000000000000000000000000000000000000000000000000014" +
				"15ee7c367f4232241028c36e720803100757c6e9000000000000000000000000" +
				"000000000000000000000000000000000000000000000000000000000000003e" +
				"62626e316d377a72356a77346b397a32327239616a676766347563616c777937" +
				"7578767539676b7736746e736d7634326c766a706b7761736167656b35670000" +
				"00000000000000000000000000000000000000000000000000000000000000b2" +
				"7b22626f6e64223a7b22616d6f756e74223a223130303030222c2273616c7422" +
				"3a22307833313333303831396135613232336439376163373134663239616535" +
				"6533616462653965656638333832333738306637613930636365363634616261" +
				"38366565222c226578706563746564223a2239373237222c2272656369706965" +
				"6e74223a2262626e3168637533306461647770686638397533783375366a327a" +
				"35387233376339616b687866637330227d7d0000000000000000000000000000",
			/* ack bytes */
			"0000000000000000000000000000000000000000000000000000000000000001" +
				"0000000000000000000000000000000000000000000000000000000000000040" +
				"0000000000000000000000000000000000000000000000000000000000000140" +
				"0000000000000000000000000000000000000000000000000000000000000020" +
				"0000000000000000000000000000000000000000000000000000000000000002" +
				"0000000000000000000000000000000000000000000000000000000000000040" +
				"00000000000000000000000000000000000000000000000000000000000000c0" +
				"0000000000000000000000000000000000000000000000000000000000000060" +
				"0000000000000000000000000000000000000000000000000000000000b0cad0" +
				"0000000000000000000000000000000000000000000000000000000000000040" +
				"0000000000000000000000000000000000000000000000000000000000000000" +
				"0000000000000000000000000000000000000000000000000000000000000020" +
				"0000000000000000000000000000000000000000000000000000000000000001",
			"15ee7c367f4232241028c36e720803100757c6e9",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			packetBytes := mustHex(tt.packetHex)
			packet, err := DecodeZkgmPacket(packetBytes)
			if err != nil {
				t.Fatalf("DecodeZkgmPacket: %v", err)
			}
			if packet.Salt[0] != 0x79 || packet.Salt[31] != 0x1f {
				t.Fatalf("salt mismatch: [0]=%x [31]=%x", packet.Salt[0], packet.Salt[31])
			}
			if packet.Path.ToString() != "0" {
				t.Fatalf("path: got %s want 0", packet.Path.ToString())
			}
			if packet.Instruction.Version != INSTR_VERSION_0 || packet.Instruction.Opcode != OP_BATCH {
				t.Fatalf("instruction: version=%d opcode=%d", packet.Instruction.Version, packet.Instruction.Opcode)
			}
			reencoded, err := EncodeZkgmPacket(packet)
			if err != nil {
				t.Fatalf("EncodeZkgmPacket: %v", err)
			}
			if !bytes.Equal(reencoded, packetBytes) {
				t.Fatalf("packet round-trip changed bytes")
			}

			batch, err := DecodeBatch(packet.Instruction.Operand)
			if err != nil {
				t.Fatalf("DecodeBatch: %v", err)
			}
			if len(batch.Instructions) != 2 {
				t.Fatalf("batch instructions: got %d want 2", len(batch.Instructions))
			}

			instr0 := batch.Instructions[0]
			if instr0.Version != INSTR_VERSION_1 || instr0.Opcode != OP_TOKEN_ORDER {
				t.Fatalf("instr[0]: version=%d opcode=%d", instr0.Version, instr0.Opcode)
			}
			tok, err := DecodeTokenOrderV1(instr0.Operand)
			if err != nil {
				t.Fatalf("DecodeTokenOrderV1: %v", err)
			}
			if hex.EncodeToString(tok.Sender) != tt.wantSender {
				t.Fatalf("tok.Sender: %x", tok.Sender)
			}
			if hex.EncodeToString(tok.BaseToken) != "e53dcec07d16d88e386ae0710e86d9a400f83c31" {
				t.Fatalf("tok.BaseToken: %x", tok.BaseToken)
			}
			if tok.BaseAmount.ToString() != "10000" {
				t.Fatalf("tok.BaseAmount: %s", tok.BaseAmount.ToString())
			}
			if tok.BaseTokenSymbol != "BABY" {
				t.Fatalf("tok.BaseTokenSymbol: %q", tok.BaseTokenSymbol)
			}
			if tok.BaseTokenName != "Babylon" {
				t.Fatalf("tok.BaseTokenName: %q", tok.BaseTokenName)
			}
			if tok.BaseTokenDecimals != 6 {
				t.Fatalf("tok.BaseTokenDecimals: %d", tok.BaseTokenDecimals)
			}
			if tok.BaseTokenPath.ToString() != "1" {
				t.Fatalf("tok.BaseTokenPath: %s", tok.BaseTokenPath.ToString())
			}
			if tok.QuoteAmount.ToString() != "10000" {
				t.Fatalf("tok.QuoteAmount: %s", tok.QuoteAmount.ToString())
			}

			instr1 := batch.Instructions[1]
			if instr1.Version != INSTR_VERSION_0 || instr1.Opcode != OP_CALL {
				t.Fatalf("instr[1]: version=%d opcode=%d", instr1.Version, instr1.Opcode)
			}
			call, err := DecodeCall(instr1.Operand)
			if err != nil {
				t.Fatalf("DecodeCall: %v", err)
			}
			if hex.EncodeToString(call.Sender) != tt.wantSender {
				t.Fatalf("call.Sender: %x", call.Sender)
			}
			if call.Eureka {
				t.Fatalf("call.Eureka: want false")
			}
			if len(call.ContractCalldata) != 178 {
				t.Fatalf("call.ContractCalldata length: got %d want 178", len(call.ContractCalldata))
			}

			ack, err := DecodeAck(mustHex(tt.ackHex))
			if err != nil {
				t.Fatalf("DecodeAck: %v", err)
			}
			if ack.Tag.ToString() != "1" {
				t.Fatalf("ack tag: got %s want 1", ack.Tag.ToString())
			}
			if len(ack.InnerAck) != 320 {
				t.Fatalf("ack inner_ack: got %d want 320", len(ack.InnerAck))
			}

			batchAck, err := DecodeBatchAck(ack.InnerAck)
			if err != nil {
				t.Fatalf("DecodeBatchAck: %v", err)
			}
			if len(batchAck.Acknowledgements) != 2 {
				t.Fatalf("batchAck len: got %d want 2", len(batchAck.Acknowledgements))
			}

			tokAck, err := DecodeTokenOrderAck(batchAck.Acknowledgements[0])
			if err != nil {
				t.Fatalf("DecodeTokenOrderAck: %v", err)
			}
			if tokAck.FillType.ToString() != "11586256" {
				t.Fatalf("tokAck.FillType: got %s want 11586256 (FILL_TYPE_PROTOCOL)", tokAck.FillType.ToString())
			}
			if len(tokAck.MarketMaker) != 0 {
				t.Fatalf("tokAck.MarketMaker: want empty, got %x", tokAck.MarketMaker)
			}
		})
	}
}

func TestFixtureVectorsJSON(t *testing.T) {
	root, err := json.Unmarshal([]byte(fixtureVectorsJSON))
	if err != nil {
		t.Fatalf("Unmarshal fixture vectors: %v", err)
	}

	vectors := root.MustArray()
	if len(vectors) != 24 {
		t.Fatalf("fixture count: got %d want 24", len(vectors))
	}

	for _, vectorNode := range vectors {
		t.Run(vectorNode.MustObject()["name"].MustString(), func(t *testing.T) {
			vector := vectorNode.MustObject()
			name := vector["name"].MustString()
			typeName := vector["type"].MustString()
			abiBytes := mustHex0x(vector["abi_hex"].MustString())
			schema, ok := schemaByType(typeName)
			if !ok {
				t.Fatalf("%s: unsupported fixture type %s", name, typeName)
			}

			decoded, err := abi.Decode(schema, abiBytes)
			if err != nil {
				t.Fatalf("%s Decode: %v", name, err)
			}
			decodedBytes, err := abi.Encode(schema, decoded)
			if err != nil {
				t.Fatalf("%s Encode(decoded): %v", name, err)
			}
			if !bytes.Equal(decodedBytes, abiBytes) {
				t.Fatalf("%s decode round-trip changed bytes", name)
			}

			assertTypedDecodeRoundTrip(t, typeName, abiBytes)

			fields := vector["fields"]
			if fields.IsNull() {
				if name != "RealPacket_msg_rs_259" {
					t.Fatalf("%s: only real packet fixture may omit fields", name)
				}
				outer, err := DecodeInstruction(abiBytes)
				if err != nil {
					t.Fatalf("%s DecodeInstruction: %v", name, err)
				}
				if outer.Version != 0 || outer.Opcode != 2 {
					t.Fatalf("%s sentinel mismatch", name)
				}
				if !bytes.Equal(outer.Operand, decoded[2].([]byte)) {
					t.Fatalf("%s operand changed during outer decode", name)
				}
				return
			}

			values, err := valuesFromFields(typeName, fields)
			if err != nil {
				t.Fatalf("%s valuesFromFields: %v", name, err)
			}
			encoded, err := abi.Encode(schema, values)
			if err != nil {
				t.Fatalf("%s Encode(fields): %v", name, err)
			}
			if !bytes.Equal(encoded, abiBytes) {
				t.Fatalf("%s\n got %s\nwant %s", name, hex.EncodeToString(encoded), hex.EncodeToString(abiBytes))
			}

			typedEncoded, err := encodeTypedFromFields(typeName, fields)
			if err != nil {
				t.Fatalf("%s encodeTypedFromFields: %v", name, err)
			}
			if !bytes.Equal(typedEncoded, abiBytes) {
				t.Fatalf("%s typed encode\n got %s\nwant %s", name, hex.EncodeToString(typedEncoded), hex.EncodeToString(abiBytes))
			}
		})
	}
}

func TestMetadataWrapperRoundTrip(t *testing.T) {
	tests := []struct {
		name string
		kind string
	}{
		{"token metadata", "token"},
		{"solver metadata", "solver"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			switch tt.kind {
			case "token":
				tok := TokenMetadata{Implementation: []byte("impl"), Initializer: mustHex("cafe")}
				tokBytes, err := EncodeTokenMetadata(tok)
				if err != nil {
					t.Fatalf("EncodeTokenMetadata: %v", err)
				}
				decodedTok, err := DecodeTokenMetadata(tokBytes)
				if err != nil {
					t.Fatalf("DecodeTokenMetadata: %v", err)
				}
				if string(decodedTok.Implementation) != "impl" || !bytes.Equal(decodedTok.Initializer, mustHex("cafe")) {
					t.Fatalf("token metadata mismatch")
				}
			case "solver":
				solver := SolverMetadata{SolverAddress: []byte("solver"), Metadata: mustHex("aabbcc")}
				solverBytes, err := EncodeSolverMetadata(solver)
				if err != nil {
					t.Fatalf("EncodeSolverMetadata: %v", err)
				}
				decodedSolver, err := DecodeSolverMetadata(solverBytes)
				if err != nil {
					t.Fatalf("DecodeSolverMetadata: %v", err)
				}
				if string(decodedSolver.SolverAddress) != "solver" || !bytes.Equal(decodedSolver.Metadata, mustHex("aabbcc")) {
					t.Fatalf("solver metadata mismatch")
				}
			}
		})
	}
}

func TestTokenMetadataRoundTrip(t *testing.T) {
	tests := []struct {
		name    string
		m       TokenMetadata
		data    []byte
		wantErr bool
	}{
		{
			name:    "empty",
			data:    []byte{},
			wantErr: true,
		},
		{
			name:    "truncated",
			data:    mustHex("0000000000000000000000000000000000000000000000000000000000000001"),
			wantErr: true,
		},
		{
			name:    "wrong layout",
			data:    mustHex("cafe"),
			wantErr: true,
		},
		{
			name: "empty values",
			m:    TokenMetadata{Implementation: []byte{}, Initializer: []byte{}},
		},
		{
			name: "grc20 implementation",
			m:    TokenMetadata{Implementation: []byte("grc20"), Initializer: mustHex("deadbeef")},
		},
		{
			name: "large initializer",
			m:    TokenMetadata{Implementation: []byte("impl"), Initializer: bytes.Repeat([]byte{0xaa}, 100)},
		},
		{
			name: "nil initializer",
			m:    TokenMetadata{Implementation: []byte("custom"), Initializer: nil},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if tt.wantErr {
				_, err := DecodeTokenMetadata(tt.data)
				if err == nil {
					t.Fatalf("expected error, got nil")
				}
				return
			}
			data, err := EncodeTokenMetadata(tt.m)
			if err != nil {
				t.Fatalf("EncodeTokenMetadata: %v", err)
			}
			decoded, err := DecodeTokenMetadata(data)
			if err != nil {
				t.Fatalf("DecodeTokenMetadata: %v", err)
			}
			if !bytes.Equal(decoded.Implementation, tt.m.Implementation) {
				t.Fatalf("implementation mismatch")
			}
			if !bytes.Equal(decoded.Initializer, tt.m.Initializer) {
				t.Fatalf("initializer mismatch")
			}
		})
	}
}

func TestSolverMetadataRoundTrip(t *testing.T) {
	tests := []struct {
		name    string
		m       SolverMetadata
		data    []byte
		wantErr bool
	}{
		{
			name:    "empty",
			data:    []byte{},
			wantErr: true,
		},
		{
			name:    "truncated",
			data:    mustHex("0000000000000000000000000000000000000000000000000000000000000001"),
			wantErr: true,
		},
		{
			name:    "wrong layout",
			data:    mustHex("cafe"),
			wantErr: true,
		},
		{
			name: "empty values",
			m:    SolverMetadata{SolverAddress: []byte{}, Metadata: []byte{}},
		},
		{
			name: "typical solver",
			m:    SolverMetadata{SolverAddress: mustHex("deadbeef"), Metadata: mustHex("0dd1a0")},
		},
		{
			name: "large metadata",
			m:    SolverMetadata{SolverAddress: mustHex("cafecafe"), Metadata: bytes.Repeat([]byte{0xbb}, 100)},
		},
		{
			name: "nil metadata",
			m:    SolverMetadata{SolverAddress: mustHex("aa"), Metadata: nil},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if tt.wantErr {
				_, err := DecodeSolverMetadata(tt.data)
				if err == nil {
					t.Fatalf("expected error, got nil")
				}
				return
			}
			data, err := EncodeSolverMetadata(tt.m)
			if err != nil {
				t.Fatalf("EncodeSolverMetadata: %v", err)
			}
			decoded, err := DecodeSolverMetadata(data)
			if err != nil {
				t.Fatalf("DecodeSolverMetadata: %v", err)
			}
			if !bytes.Equal(decoded.SolverAddress, tt.m.SolverAddress) {
				t.Fatalf("solver_address mismatch")
			}
			if !bytes.Equal(decoded.Metadata, tt.m.Metadata) {
				t.Fatalf("metadata mismatch")
			}
		})
	}
}

func TestInstructionValues(t *testing.T) {
	tests := []struct {
		name string
		ins  Instruction
	}{
		{"call", Instruction{Version: INSTR_VERSION_0, Opcode: OP_CALL, Operand: []byte("call")}},
		{"token order", Instruction{Version: INSTR_VERSION_1, Opcode: OP_TOKEN_ORDER, Operand: mustHex("cafe")}},
		{"empty operand", Instruction{Version: INSTR_VERSION_0, Opcode: OP_BATCH, Operand: []byte{}}},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := instructionValues(tt.ins)
			if len(got) != 3 {
				t.Fatalf("len: got %d want 3", len(got))
			}
			if got[0].(uint8) != tt.ins.Version {
				t.Fatalf("version: got %d want %d", got[0].(uint8), tt.ins.Version)
			}
			if got[1].(uint8) != tt.ins.Opcode {
				t.Fatalf("opcode: got %d want %d", got[1].(uint8), tt.ins.Opcode)
			}
			if !bytes.Equal(got[2].([]byte), tt.ins.Operand) {
				t.Fatalf("operand: got %x want %x", got[2].([]byte), tt.ins.Operand)
			}
		})
	}
}

func TestInstructionFromValues(t *testing.T) {
	tests := []struct {
		name   string
		values []any
		want   Instruction
	}{
		{
			"call",
			[]any{uint8(INSTR_VERSION_0), uint8(OP_CALL), []byte("call")},
			Instruction{Version: INSTR_VERSION_0, Opcode: OP_CALL, Operand: []byte("call")},
		},
		{
			"token order",
			[]any{uint8(INSTR_VERSION_1), uint8(OP_TOKEN_ORDER), mustHex("cafe")},
			Instruction{Version: INSTR_VERSION_1, Opcode: OP_TOKEN_ORDER, Operand: mustHex("cafe")},
		},
		{
			"empty operand",
			[]any{uint8(INSTR_VERSION_0), uint8(OP_BATCH), []byte{}},
			Instruction{Version: INSTR_VERSION_0, Opcode: OP_BATCH, Operand: []byte{}},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := instructionFromValues(tt.values)
			if got.Version != tt.want.Version {
				t.Fatalf("version: got %d want %d", got.Version, tt.want.Version)
			}
			if got.Opcode != tt.want.Opcode {
				t.Fatalf("opcode: got %d want %d", got.Opcode, tt.want.Opcode)
			}
			if !bytes.Equal(got.Operand, tt.want.Operand) {
				t.Fatalf("operand: got %x want %x", got.Operand, tt.want.Operand)
			}
		})
	}
}

func TestEncodeZkgmPacket(t *testing.T) {
	tests := []struct {
		name string
		salt [32]byte
		path *u256.Uint
		ins  Instruction
	}{
		{
			"minimal packet",
			[32]byte{0x01, 0x02},
			u256.NewUint(123),
			Instruction{Version: INSTR_VERSION_0, Opcode: OP_CALL, Operand: []byte("operand")},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			data, err := EncodeZkgmPacket(ZkgmPacket{Salt: tt.salt, Path: tt.path, Instruction: tt.ins})
			if err != nil {
				t.Fatalf("EncodeZkgmPacket: %v", err)
			}
			decoded, err := DecodeZkgmPacket(data)
			if err != nil {
				t.Fatalf("DecodeZkgmPacket: %v", err)
			}
			if decoded.Salt[0] != tt.salt[0] || decoded.Salt[1] != tt.salt[1] {
				t.Fatalf("salt mismatch")
			}
			if decoded.Path.ToString() != "123" {
				t.Fatalf("path: got %s want 123", decoded.Path.ToString())
			}
			if decoded.Instruction.Version != tt.ins.Version || decoded.Instruction.Opcode != tt.ins.Opcode {
				t.Fatalf("instruction mismatch")
			}
		})
	}
}

func TestDecodeZkgmPacketErrors(t *testing.T) {
	tests := []struct {
		name string
		data []byte
	}{
		{"empty", []byte{}},
		{"truncated", mustHex("00" + "01" + "00")},
		{"wrong layout - invalid salt offset", mustHex("0000000000000000000000000000000000000000000000000000000000000020")},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, err := DecodeZkgmPacket(tt.data)
			if err == nil {
				t.Fatalf("expected error, got nil")
			}
		})
	}
}

func TestEncodeForward(t *testing.T) {
	tests := []struct {
		name             string
		f                Forward
		wantPath         string
		wantTimeoutHeight uint64
		wantTimeoutTimestamp uint64
	}{
		{
			name: "zero values",
			f: Forward{
				Path:             u256.NewUint(0),
				TimeoutHeight:    0,
				TimeoutTimestamp: 0,
				Instruction:      Instruction{Version: INSTR_VERSION_0, Opcode: OP_CALL, Operand: []byte{}},
			},
			wantPath:         "0",
			wantTimeoutHeight: 0,
			wantTimeoutTimestamp: 0,
		},
		{
			name: "typical values",
			f: Forward{
				Path:             u256.NewUint(456),
				TimeoutHeight:    1000,
				TimeoutTimestamp: 2000,
				Instruction:      Instruction{Version: INSTR_VERSION_0, Opcode: OP_BATCH, Operand: []byte{}},
			},
			wantPath:         "456",
			wantTimeoutHeight: 1000,
			wantTimeoutTimestamp: 2000,
		},
		{
			name: "large timeouts",
			f: Forward{
				Path:             u256.NewUint(99999),
				TimeoutHeight:    18446744073709551615,
				TimeoutTimestamp: 18446744073709551615,
				Instruction:      Instruction{Version: INSTR_VERSION_1, Opcode: OP_TOKEN_ORDER, Operand: []byte{0xab}},
			},
			wantPath:         "99999",
			wantTimeoutHeight: 18446744073709551615,
			wantTimeoutTimestamp: 18446744073709551615,
		},
		{
			name: "large operand",
			f: Forward{
				Path:             u256.NewUint(12345),
				TimeoutHeight:    5000,
				TimeoutTimestamp: 10000,
				Instruction:      Instruction{Version: INSTR_VERSION_0, Opcode: OP_CALL, Operand: bytes.Repeat([]byte{0xcc}, 100)},
			},
			wantPath:         "12345",
			wantTimeoutHeight: 5000,
			wantTimeoutTimestamp: 10000,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			data, err := EncodeForward(tt.f)
			if err != nil {
				t.Fatalf("EncodeForward: %v", err)
			}
			decoded, err := DecodeForward(data)
			if err != nil {
				t.Fatalf("DecodeForward: %v", err)
			}
			if decoded.Path.ToString() != tt.wantPath {
				t.Fatalf("path: got %s want %s", decoded.Path.ToString(), tt.wantPath)
			}
			if decoded.TimeoutHeight != tt.wantTimeoutHeight {
				t.Fatalf("timeout_height: got %d want %d", decoded.TimeoutHeight, tt.wantTimeoutHeight)
			}
			if decoded.TimeoutTimestamp != tt.wantTimeoutTimestamp {
				t.Fatalf("timeout_timestamp: got %d want %d", decoded.TimeoutTimestamp, tt.wantTimeoutTimestamp)
			}
		})
	}
}

func TestDecodeForward(t *testing.T) {
	tests := []struct {
		name       string
		data       []byte
		want       Forward
		wantErr    bool
	}{
		{
			name:    "empty",
			data:    []byte{},
			wantErr: true,
		},
		{
			name:    "truncated",
			data:    mustHex("0000000000000000000000000000000000000000000000000000000000000001"),
			wantErr: true,
		},
		{
			name:    "wrong layout",
			data:    mustHex("00"),
			wantErr: true,
		},
		{
			name: "minimal values",
			data: mustEncodeForward(Forward{
				Path: u256.NewUint(0),
				TimeoutHeight:    0,
				TimeoutTimestamp: 0,
				Instruction:      Instruction{Version: INSTR_VERSION_0, Opcode: OP_CALL, Operand: []byte{}},
			}),
			want: Forward{
				Path: u256.NewUint(0),
				TimeoutHeight:    0,
				TimeoutTimestamp: 0,
				Instruction:      Instruction{Version: INSTR_VERSION_0, Opcode: OP_CALL, Operand: []byte{}},
			},
		},
		{
			name: "typical values",
			data: mustEncodeForward(Forward{
				Path: u256.NewUint(123),
				TimeoutHeight:    5000,
				TimeoutTimestamp: 10000,
				Instruction:      Instruction{Version: INSTR_VERSION_0, Opcode: OP_BATCH, Operand: []byte{0xab, 0xcd}},
			}),
			want: Forward{
				Path: u256.NewUint(123),
				TimeoutHeight:    5000,
				TimeoutTimestamp: 10000,
				Instruction:      Instruction{Version: INSTR_VERSION_0, Opcode: OP_BATCH, Operand: []byte{0xab, 0xcd}},
			},
		},
		{
			name: "large path and timeouts",
			data: mustEncodeForward(Forward{
				Path: u256.NewUint(18446744073709551615),
				TimeoutHeight:    18446744073709551615,
				TimeoutTimestamp: 18446744073709551615,
				Instruction:      Instruction{Version: INSTR_VERSION_1, Opcode: OP_TOKEN_ORDER, Operand: []byte{0xff}},
			}),
			want: Forward{
				Path: u256.NewUint(18446744073709551615),
				TimeoutHeight:    18446744073709551615,
				TimeoutTimestamp: 18446744073709551615,
				Instruction:      Instruction{Version: INSTR_VERSION_1, Opcode: OP_TOKEN_ORDER, Operand: []byte{0xff}},
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := DecodeForward(tt.data)
			if tt.wantErr {
				if err == nil {
					t.Fatalf("expected error, got nil")
				}
				return
			}
			if err != nil {
				t.Fatalf("DecodeForward: %v", err)
			}
			if got.Path.ToString() != tt.want.Path.ToString() {
				t.Fatalf("path: got %s want %s", got.Path.ToString(), tt.want.Path.ToString())
			}
			if got.TimeoutHeight != tt.want.TimeoutHeight {
				t.Fatalf("timeout_height: got %d want %d", got.TimeoutHeight, tt.want.TimeoutHeight)
			}
			if got.TimeoutTimestamp != tt.want.TimeoutTimestamp {
				t.Fatalf("timeout_timestamp: got %d want %d", got.TimeoutTimestamp, tt.want.TimeoutTimestamp)
			}
			if got.Instruction.Version != tt.want.Instruction.Version {
				t.Fatalf("instruction version: got %d want %d", got.Instruction.Version, tt.want.Instruction.Version)
			}
			if got.Instruction.Opcode != tt.want.Instruction.Opcode {
				t.Fatalf("instruction opcode: got %d want %d", got.Instruction.Opcode, tt.want.Instruction.Opcode)
			}
			if !bytes.Equal(got.Instruction.Operand, tt.want.Instruction.Operand) {
				t.Fatalf("instruction operand: got %x want %x", got.Instruction.Operand, tt.want.Instruction.Operand)
			}
		})
	}
}

func TestCallRoundTrip(t *testing.T) {
	tests := []struct {
		name    string
		c       Call
		data    []byte
		wantErr bool
	}{
		{
			name:    "empty",
			data:    []byte{},
			wantErr: true,
		},
		{
			name:    "truncated",
			data:    mustHex("0000000000000000000000000000000000000000000000000000000000000001"),
			wantErr: true,
		},
		{
			name:    "wrong layout",
			data:    mustHex("cafe"),
			wantErr: true,
		},
		{
			name: "minimal values",
			c:    Call{Sender: []byte{}, Eureka: false, ContractAddress: []byte{}, ContractCalldata: []byte{}},
		},
		{
			name: "typical values",
			c:    Call{Sender: mustHex("aabbccdd"), Eureka: false, ContractAddress: mustHex("deadbeef"), ContractCalldata: []byte("calldata")},
		},
		{
			name: "eureka enabled",
			c:    Call{Sender: mustHex("ffee"), Eureka: true, ContractAddress: mustHex("ddbb"), ContractCalldata: []byte("data")},
		},
		{
			name: "large calldata",
			c:    Call{Sender: mustHex("deadbeefdeadbeef"), Eureka: false, ContractAddress: mustHex("cafecafecafe"), ContractCalldata: bytes.Repeat([]byte{0xcc}, 100)},
		},
		{
			name: "nil calldata",
			c:    Call{Sender: mustHex("aa"), Eureka: false, ContractAddress: mustHex("bb"), ContractCalldata: nil},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if tt.wantErr {
				_, err := DecodeCall(tt.data)
				if err == nil {
					t.Fatalf("expected error, got nil")
				}
				return
			}
			data, err := EncodeCall(tt.c)
			if err != nil {
				t.Fatalf("EncodeCall: %v", err)
			}
			decoded, err := DecodeCall(data)
			if err != nil {
				t.Fatalf("DecodeCall: %v", err)
			}
			if !bytes.Equal(decoded.Sender, tt.c.Sender) {
				t.Fatalf("sender mismatch")
			}
			if decoded.Eureka != tt.c.Eureka {
				t.Fatalf("eureka: got %v want %v", decoded.Eureka, tt.c.Eureka)
			}
			if !bytes.Equal(decoded.ContractAddress, tt.c.ContractAddress) {
				t.Fatalf("contract_address mismatch")
			}
			if !bytes.Equal(decoded.ContractCalldata, tt.c.ContractCalldata) {
				t.Fatalf("contract_calldata mismatch")
			}
		})
	}
}

func TestEncodeBatch(t *testing.T) {
	tests := []struct {
		name             string
		b                Batch
		wantInstrCount   int
	}{
		{
			name: "empty instructions",
			b:    Batch{Instructions: []Instruction{}},
			wantInstrCount: 0,
		},
		{
			name: "single instruction",
			b: Batch{Instructions: []Instruction{
				{Version: INSTR_VERSION_0, Opcode: OP_CALL, Operand: []byte("call1")},
			}},
			wantInstrCount: 1,
		},
		{
			name: "two call instructions",
			b: Batch{Instructions: []Instruction{
				{Version: INSTR_VERSION_0, Opcode: OP_CALL, Operand: []byte("call1")},
				{Version: INSTR_VERSION_0, Opcode: OP_CALL, Operand: []byte("call2")},
			}},
			wantInstrCount: 2,
		},
		{
			name: "mixed instruction types",
			b: Batch{Instructions: []Instruction{
				{Version: INSTR_VERSION_1, Opcode: OP_TOKEN_ORDER, Operand: []byte{0xab, 0xcd}},
				{Version: INSTR_VERSION_0, Opcode: OP_BATCH, Operand: []byte{}},
				{Version: INSTR_VERSION_0, Opcode: OP_CALL, Operand: []byte("data")},
			}},
			wantInstrCount: 3,
		},
		{
			name: "instruction with large operand",
			b: Batch{Instructions: []Instruction{
				{Version: INSTR_VERSION_0, Opcode: OP_CALL, Operand: bytes.Repeat([]byte{0xff}, 200)},
			}},
			wantInstrCount: 1,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			data, err := EncodeBatch(tt.b)
			if err != nil {
				t.Fatalf("EncodeBatch: %v", err)
			}
			decoded, err := DecodeBatch(data)
			if err != nil {
				t.Fatalf("DecodeBatch: %v", err)
			}
			if len(decoded.Instructions) != tt.wantInstrCount {
				t.Fatalf("instructions count: got %d want %d", len(decoded.Instructions), tt.wantInstrCount)
			}
			for i := range tt.b.Instructions {
				if !bytes.Equal(decoded.Instructions[i].Operand, tt.b.Instructions[i].Operand) {
					t.Fatalf("instruction[%d] operand mismatch", i)
				}
			}
		})
	}
}

func TestDecodeBatchErrors(t *testing.T) {
	tests := []struct {
		name string
		data []byte
	}{
		{"empty", []byte{}},
		{"truncated array", mustHex("00000000000000000000000000000000000000000000000000000000000000200000000000000001")},
		{"wrong layout", mustHex("cafe")},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, err := DecodeBatch(tt.data)
			if err == nil {
				t.Fatalf("expected error, got nil")
			}
		})
	}
}

func TestEncodeTokenOrderV1(t *testing.T) {
	tests := []struct {
		name string
		o    TokenOrderV1
	}{
		{
			name: "minimal values",
			o: TokenOrderV1{
				Sender:            mustHex("aa"),
				Receiver:          mustHex("bb"),
				BaseToken:         mustHex("00112233445566778899aabbccddeeff"),
				BaseAmount:        u256.NewUint(1),
				BaseTokenSymbol:   "T",
				BaseTokenName:     "T",
				BaseTokenDecimals: 0,
				BaseTokenPath:     u256.NewUint(0),
				QuoteToken:        mustHex("ffeeddccbbaa99887766554433221100"),
				QuoteAmount:       u256.NewUint(1),
			},
		},
		{
			name: "typical values",
			o: TokenOrderV1{
				Sender:            mustHex("aabbccdd"),
				Receiver:          mustHex("ddeeffaa"),
				BaseToken:         mustHex("00112233445566778899aabbccddeeff"),
				BaseAmount:        u256.NewUint(10000),
				BaseTokenSymbol:   "TEST",
				BaseTokenName:     "Test Token",
				BaseTokenDecimals: 18,
				BaseTokenPath:     u256.NewUint(1),
				QuoteToken:        mustHex("00112233445566778899aabbccddeeff"),
				QuoteAmount:       u256.NewUint(20000),
			},
		},
		{
			name: "large amounts",
			o: TokenOrderV1{
				Sender:            mustHex("deadbeef"),
				Receiver:          mustHex("cafedead"),
				BaseToken:         mustHex("11112222333344445555666677778888"),
				BaseAmount:        u256.NewUint(1000000000000000000),
				BaseTokenSymbol:   "ABC",
				BaseTokenName:     "Abc Token",
				BaseTokenDecimals: 6,
				BaseTokenPath:     u256.NewUint(999),
				QuoteToken:        mustHex("88887777666655554444333322221111"),
				QuoteAmount:       u256.NewUint(5000000000000),
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			data, err := EncodeTokenOrderV1(tt.o)
			if err != nil {
				t.Fatalf("EncodeTokenOrderV1: %v", err)
			}
			decoded, err := DecodeTokenOrderV1(data)
			if err != nil {
				t.Fatalf("DecodeTokenOrderV1: %v", err)
			}
			if !bytes.Equal(decoded.Sender, tt.o.Sender) {
				t.Fatalf("sender mismatch")
			}
			if !bytes.Equal(decoded.Receiver, tt.o.Receiver) {
				t.Fatalf("receiver mismatch")
			}
			if decoded.BaseAmount.ToString() != tt.o.BaseAmount.ToString() {
				t.Fatalf("base_amount: got %s want %s", decoded.BaseAmount.ToString(), tt.o.BaseAmount.ToString())
			}
			if decoded.BaseTokenSymbol != tt.o.BaseTokenSymbol {
				t.Fatalf("base_token_symbol: got %s want %s", decoded.BaseTokenSymbol, tt.o.BaseTokenSymbol)
			}
			if decoded.BaseTokenName != tt.o.BaseTokenName {
				t.Fatalf("base_token_name: got %s want %s", decoded.BaseTokenName, tt.o.BaseTokenName)
			}
			if decoded.BaseTokenDecimals != tt.o.BaseTokenDecimals {
				t.Fatalf("base_token_decimals: got %d want %d", decoded.BaseTokenDecimals, tt.o.BaseTokenDecimals)
			}
			if decoded.BaseTokenPath.ToString() != tt.o.BaseTokenPath.ToString() {
				t.Fatalf("base_token_path: got %s want %s", decoded.BaseTokenPath.ToString(), tt.o.BaseTokenPath.ToString())
			}
			if decoded.QuoteAmount.ToString() != tt.o.QuoteAmount.ToString() {
				t.Fatalf("quote_amount: got %s want %s", decoded.QuoteAmount.ToString(), tt.o.QuoteAmount.ToString())
			}
		})
	}
}

func TestDecodeTokenOrderV1Errors(t *testing.T) {
	tests := []struct {
		name string
		data []byte
	}{
		{"empty", []byte{}},
		{"truncated", mustHex("aabb")},
		{"wrong layout", mustHex("cafe")},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, err := DecodeTokenOrderV1(tt.data)
			if err == nil {
				t.Fatalf("expected error, got nil")
			}
		})
	}
}

func TestEncodeTokenOrderV2(t *testing.T) {
	tests := []struct {
		name string
		o    TokenOrderV2
	}{
		{
			name: "minimal values",
			o: TokenOrderV2{
				Sender:      mustHex("aa"),
				Receiver:    mustHex("bb"),
				BaseToken:   mustHex("00112233445566778899aabbccddeeff"),
				BaseAmount:  u256.NewUint(1),
				QuoteToken:  mustHex("ffeeddccbbaa99887766554433221100"),
				QuoteAmount: u256.NewUint(1),
				Kind:        0,
				Metadata:    []byte{},
			},
		},
		{
			name: "typical values",
			o: TokenOrderV2{
				Sender:      mustHex("aabbccdd"),
				Receiver:    mustHex("ddeeffaa"),
				BaseToken:   mustHex("00112233445566778899aabbccddeeff"),
				BaseAmount:  u256.NewUint(10000),
				QuoteToken:  mustHex("ffeeddccbbaa99887766554433221100"),
				QuoteAmount: u256.NewUint(20000),
				Kind:        1,
				Metadata:    mustHex("deadbeef"),
			},
		},
		{
			name: "large amounts with metadata",
			o: TokenOrderV2{
				Sender:      mustHex("deadbeefdeadbeef"),
				Receiver:    mustHex("cafecafecafecafe"),
				BaseToken:   mustHex("11112222333344445555666677778888"),
				BaseAmount:  u256.NewUint(1000000000000000000),
				QuoteToken:  mustHex("88887777666655554444333322221111"),
				QuoteAmount: u256.NewUint(5000000000000),
				Kind:        255,
				Metadata:    bytes.Repeat([]byte{0xab}, 50),
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			data, err := EncodeTokenOrderV2(tt.o)
			if err != nil {
				t.Fatalf("EncodeTokenOrderV2: %v", err)
			}
			decoded, err := DecodeTokenOrderV2(data)
			if err != nil {
				t.Fatalf("DecodeTokenOrderV2: %v", err)
			}
			if !bytes.Equal(decoded.Sender, tt.o.Sender) {
				t.Fatalf("sender mismatch")
			}
			if !bytes.Equal(decoded.Receiver, tt.o.Receiver) {
				t.Fatalf("receiver mismatch")
			}
			if decoded.BaseAmount.ToString() != tt.o.BaseAmount.ToString() {
				t.Fatalf("base_amount: got %s want %s", decoded.BaseAmount.ToString(), tt.o.BaseAmount.ToString())
			}
			if decoded.QuoteAmount.ToString() != tt.o.QuoteAmount.ToString() {
				t.Fatalf("quote_amount: got %s want %s", decoded.QuoteAmount.ToString(), tt.o.QuoteAmount.ToString())
			}
			if decoded.Kind != tt.o.Kind {
				t.Fatalf("kind: got %d want %d", decoded.Kind, tt.o.Kind)
			}
			if !bytes.Equal(decoded.Metadata, tt.o.Metadata) {
				t.Fatalf("metadata mismatch")
			}
		})
	}
}

func TestDecodeTokenOrderV2Errors(t *testing.T) {
	tests := []struct {
		name string
		data []byte
	}{
		{"empty", []byte{}},
		{"truncated", mustHex("aabb")},
		{"wrong layout", mustHex("cafe")},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, err := DecodeTokenOrderV2(tt.data)
			if err == nil {
				t.Fatalf("expected error, got nil")
			}
		})
	}
}

func TestTokenInitializerRoundTrip(t *testing.T) {
	tests := []struct {
		name    string
		ti      TokenInitializer
		data    []byte
		wantErr bool
	}{
		{
			name:    "empty",
			data:    []byte{},
			wantErr: true,
		},
		{
			name:    "truncated",
			data:    mustHex("0000000000000000000000000000000000000000000000000000000000000020"),
			wantErr: true,
		},
		{
			name:    "wrong layout",
			data:    mustHex("cafe"),
			wantErr: true,
		},
		{
			name: "minimal values",
			ti:   TokenInitializer{Name: "", Symbol: "", Decimals: 0},
		},
		{
			name: "typical token",
			ti:   TokenInitializer{Name: "Test Token", Symbol: "TST", Decimals: 18},
		},
		{
			name: "maximum decimals",
			ti:   TokenInitializer{Name: "USD Coin", Symbol: "USDC", Decimals: 255},
		},
		{
			name: "single character name and symbol",
			ti:   TokenInitializer{Name: "A", Symbol: "B", Decimals: 6},
		},
		{
			name: "long name and symbol",
			ti:   TokenInitializer{Name: "Very Long Token Name With Many Words", Symbol: "VLONG", Decimals: 12},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if tt.wantErr {
				_, err := DecodeTokenInitializer(tt.data)
				if err == nil {
					t.Fatalf("expected error, got nil")
				}
				return
			}
			data, err := EncodeTokenInitializer(tt.ti)
			if err != nil {
				t.Fatalf("EncodeTokenInitializer: %v", err)
			}
			decoded, err := DecodeTokenInitializer(data)
			if err != nil {
				t.Fatalf("DecodeTokenInitializer: %v", err)
			}
			if decoded.Name != tt.ti.Name {
				t.Fatalf("name: got %q want %q", decoded.Name, tt.ti.Name)
			}
			if decoded.Symbol != tt.ti.Symbol {
				t.Fatalf("symbol: got %q want %q", decoded.Symbol, tt.ti.Symbol)
			}
			if decoded.Decimals != tt.ti.Decimals {
				t.Fatalf("decimals: got %d want %d", decoded.Decimals, tt.ti.Decimals)
			}
		})
	}
}

func TestEncodeAck(t *testing.T) {
	tests := []struct {
		name string
		a    Ack
	}{
		{
			name: "zero values",
			a:    Ack{Tag: u256.NewUint(0), InnerAck: []byte{}},
		},
		{
			name: "typical values",
			a:    Ack{Tag: u256.NewUint(12345), InnerAck: mustHex("deadbeef")},
		},
		{
			name: "large tag and inner ack",
			a:    Ack{Tag: u256.NewUint(18446744073709551615), InnerAck: bytes.Repeat([]byte{0xcc}, 100)},
		},
		{
			name: "nil inner ack",
			a:    Ack{Tag: u256.NewUint(1), InnerAck: nil},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			data, err := EncodeAck(tt.a)
			if err != nil {
				t.Fatalf("EncodeAck: %v", err)
			}
			decoded, err := DecodeAck(data)
			if err != nil {
				t.Fatalf("DecodeAck: %v", err)
			}
			if decoded.Tag.ToString() != tt.a.Tag.ToString() {
				t.Fatalf("tag: got %s want %s", decoded.Tag.ToString(), tt.a.Tag.ToString())
			}
			if !bytes.Equal(decoded.InnerAck, tt.a.InnerAck) {
				t.Fatalf("inner_ack mismatch")
			}
		})
	}
}

func TestDecodeAckErrors(t *testing.T) {
	tests := []struct {
		name string
		data []byte
	}{
		{"empty", []byte{}},
		{"truncated", mustHex("0000000000000000000000000000000000000000000000000000000000000001")},
		{"wrong layout", mustHex("cafe")},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, err := DecodeAck(tt.data)
			if err == nil {
				t.Fatalf("expected error, got nil")
			}
		})
	}
}

func TestEncodeBatchAck(t *testing.T) {
	tests := []struct {
		name              string
		ba                BatchAck
		wantAckCount      int
	}{
		{
			name:         "empty acknowledgements",
			ba:           BatchAck{Acknowledgements: [][]byte{}},
			wantAckCount: 0,
		},
		{
			name: "single acknowledgement",
			ba: BatchAck{Acknowledgements: [][]byte{
				mustHex("dead"),
			}},
			wantAckCount: 1,
		},
		{
			name: "three acknowledgements",
			ba: BatchAck{Acknowledgements: [][]byte{
				mustHex("dead"),
				mustHex("beef"),
				mustHex("cafe"),
			}},
			wantAckCount: 3,
		},
		{
			name: "mixed nil and non-nil",
			ba: BatchAck{Acknowledgements: [][]byte{
				mustHex("aa"),
				nil,
				mustHex("bb"),
			}},
			wantAckCount: 3,
		},
		{
			name: "large acknowledgement",
			ba: BatchAck{Acknowledgements: [][]byte{
				bytes.Repeat([]byte{0xdd}, 200),
			}},
			wantAckCount: 1,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			data, err := EncodeBatchAck(tt.ba)
			if err != nil {
				t.Fatalf("EncodeBatchAck: %v", err)
			}
			decoded, err := DecodeBatchAck(data)
			if err != nil {
				t.Fatalf("DecodeBatchAck: %v", err)
			}
			if len(decoded.Acknowledgements) != tt.wantAckCount {
				t.Fatalf("acknowledgements count: got %d want %d", len(decoded.Acknowledgements), tt.wantAckCount)
			}
			for i := range tt.ba.Acknowledgements {
				if !bytes.Equal(decoded.Acknowledgements[i], tt.ba.Acknowledgements[i]) {
					t.Fatalf("ack[%d] mismatch", i)
				}
			}
		})
	}
}

func TestDecodeBatchAckErrors(t *testing.T) {
	tests := []struct {
		name string
		data []byte
	}{
		{"empty", []byte{}},
		{"truncated array", mustHex("00000000000000000000000000000000000000000000000000000000000000200000000000000002dead")},
		{"wrong layout", mustHex("cafe")},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, err := DecodeBatchAck(tt.data)
			if err == nil {
				t.Fatalf("expected error, got nil")
			}
		})
	}
}

func TestEncodeTokenOrderAck(t *testing.T) {
	tests := []struct {
		name string
		toa  TokenOrderAck
	}{
		{
			name: "zero values",
			toa:  TokenOrderAck{FillType: u256.NewUint(0), MarketMaker: []byte{}},
		},
		{
			name: "typical values",
			toa:  TokenOrderAck{FillType: u256.NewUint(999), MarketMaker: mustHex("aabbcc")},
		},
		{
			name: "large fill type",
			toa:  TokenOrderAck{FillType: u256.NewUint(1000000000000000000), MarketMaker: mustHex("deadbeefdeadbeef")},
		},
		{
			name: "nil market maker",
			toa:  TokenOrderAck{FillType: u256.NewUint(123), MarketMaker: nil},
		},
		{
			name: "large market maker",
			toa:  TokenOrderAck{FillType: u256.NewUint(456), MarketMaker: bytes.Repeat([]byte{0xee}, 100)},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			data, err := EncodeTokenOrderAck(tt.toa)
			if err != nil {
				t.Fatalf("EncodeTokenOrderAck: %v", err)
			}
			decoded, err := DecodeTokenOrderAck(data)
			if err != nil {
				t.Fatalf("DecodeTokenOrderAck: %v", err)
			}
			if decoded.FillType.ToString() != tt.toa.FillType.ToString() {
				t.Fatalf("fill_type: got %s want %s", decoded.FillType.ToString(), tt.toa.FillType.ToString())
			}
			if !bytes.Equal(decoded.MarketMaker, tt.toa.MarketMaker) {
				t.Fatalf("market_maker mismatch")
			}
		})
	}
}

func TestDecodeTokenOrderAckErrors(t *testing.T) {
	tests := []struct {
		name string
		data []byte
	}{
		{"empty", []byte{}},
		{"truncated", mustHex("0000000000000000000000000000000000000000000000000000000000000001")},
		{"wrong layout", mustHex("cafe")},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, err := DecodeTokenOrderAck(tt.data)
			if err == nil {
				t.Fatalf("expected error, got nil")
			}
		})
	}
}

func TestDecodeTokenInitializerFromMetadata(t *testing.T) {
	validInit, err := EncodeTokenInitializer(TokenInitializer{Name: "Test Token", Symbol: "TST", Decimals: 18})
	if err != nil {
		t.Fatalf("EncodeTokenInitializer: %v", err)
	}

	// Real ZkgmERC20 implementation address and initialize(address,address,
	// string,string,uint8) calldata for name="footoken", symbol="foo",
	// decimals=6, captured from a live `cast calldata` run against the
	// deployed Sepolia contract (selector 0x8420ce99).
	evmImplementation := mustHex("af739f34ddf951cbc24fdbba4f76213688e13627")
	evmInitializer := mustHex0x("0x8420ce9900000000000000000000000040cdff51ae7487e0b4a4d6e5f86eb15fb7c1d9f40000000000000000000000005fbe74a283f7954f10aa04c2edf55578811aeb0300000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000e000000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000008666f6f746f6b656e0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003666f6f0000000000000000000000000000000000000000000000000000000000")

	tests := []struct {
		name string
		meta TokenMetadata
		want TokenInitializer
	}{
		{
			"valid grc20 metadata",
			TokenMetadata{Implementation: []byte("grc20"), Initializer: validInit},
			TokenInitializer{Name: "Test Token", Symbol: "TST", Decimals: 18},
		},
		{
			"invalid grc20 initializer",
			TokenMetadata{Implementation: []byte("grc20"), Initializer: []byte("truncated")},
			TokenInitializer{},
		},
		{
			"unknown implementation",
			TokenMetadata{Implementation: []byte("unknown"), Initializer: []byte("whatever")},
			TokenInitializer{},
		},
		{
			"empty implementation",
			TokenMetadata{Implementation: []byte{}, Initializer: []byte{}},
			TokenInitializer{},
		},
		{
			"valid evm erc20 metadata",
			TokenMetadata{Implementation: evmImplementation, Initializer: evmInitializer},
			TokenInitializer{Name: "footoken", Symbol: "foo", Decimals: 6},
		},
		{
			"evm implementation wrong selector",
			TokenMetadata{Implementation: evmImplementation, Initializer: append([]byte{0xde, 0xad, 0xbe, 0xef}, evmInitializer[4:]...)},
			TokenInitializer{},
		},
		{
			"evm implementation truncated calldata",
			TokenMetadata{Implementation: evmImplementation, Initializer: evmInitializer[:4]},
			TokenInitializer{},
		},
		{
			"20-byte implementation that is not valid erc20 calldata",
			TokenMetadata{Implementation: evmImplementation, Initializer: []byte("not calldata")},
			TokenInitializer{},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := DecodeTokenInitializerFromMetadata(tt.meta)
			if got != tt.want {
				t.Fatalf("got %v want %v", got, tt.want)
			}
		})
	}
}

func schemaByType(typeName string) (abi.Schema, bool) {
	switch typeName {
	case "Instruction":
		return InstructionSchema, true
	case "Call":
		return CallSchema, true
	case "ZkgmPacket":
		return ZkgmPacketSchema, true
	case "Forward":
		return ForwardSchema, true
	case "Batch":
		return BatchSchema, true
	case "TokenOrderV1":
		return TokenOrderV1Schema, true
	case "TokenOrderV2":
		return TokenOrderV2Schema, true
	case "Ack":
		return AckSchema, true
	case "BatchAck":
		return BatchAckSchema, true
	case "TokenOrderAck":
		return TokenOrderAckSchema, true
	default:
		return abi.Schema{}, false
	}
}

func valuesFromFields(typeName string, node *json.Node) ([]any, error) {
	fields := node.MustObject()
	switch typeName {
	case "Instruction":
		return fixtureInstructionValues(fields), nil
	case "Call":
		return []any{
			bytesField(fields, "sender"),
			fields["eureka"].MustBool(),
			bytesField(fields, "contract_address"),
			bytesField(fields, "contract_calldata"),
		}, nil
	case "ZkgmPacket":
		salt, err := bytes32Field(fields, "salt")
		if err != nil {
			return nil, err
		}
		path, err := uint256Field(fields, "path")
		if err != nil {
			return nil, err
		}
		return []any{
			salt,
			path,
			fixtureInstructionValues(fields["instruction"].MustObject()),
		}, nil
	case "Forward":
		path, err := uint256Field(fields, "path")
		if err != nil {
			return nil, err
		}
		timeoutHeight, err := uint64Field(fields, "timeout_height")
		if err != nil {
			return nil, err
		}
		timeoutTimestamp, err := uint64Field(fields, "timeout_timestamp")
		if err != nil {
			return nil, err
		}
		return []any{
			path,
			timeoutHeight,
			timeoutTimestamp,
			fixtureInstructionValues(fields["instruction"].MustObject()),
		}, nil
	case "Batch":
		arr := fields["instructions"].MustArray()
		instructions := make([]any, len(arr))
		for i, elem := range arr {
			instructions[i] = fixtureInstructionValues(elem.MustObject())
		}
		return []any{instructions}, nil
	case "TokenOrderV1":
		baseAmount, err := uint256Field(fields, "base_amount")
		if err != nil {
			return nil, err
		}
		basePath, err := uint256Field(fields, "base_token_path")
		if err != nil {
			return nil, err
		}
		quoteAmount, err := uint256Field(fields, "quote_amount")
		if err != nil {
			return nil, err
		}
		return []any{
			bytesField(fields, "sender"),
			bytesField(fields, "receiver"),
			bytesField(fields, "base_token"),
			baseAmount,
			fields["base_token_symbol"].MustString(),
			fields["base_token_name"].MustString(),
			uint8Field(fields, "base_token_decimals"),
			basePath,
			bytesField(fields, "quote_token"),
			quoteAmount,
		}, nil
	case "TokenOrderV2":
		baseAmount, err := uint256Field(fields, "base_amount")
		if err != nil {
			return nil, err
		}
		quoteAmount, err := uint256Field(fields, "quote_amount")
		if err != nil {
			return nil, err
		}
		return []any{
			bytesField(fields, "sender"),
			bytesField(fields, "receiver"),
			bytesField(fields, "base_token"),
			baseAmount,
			bytesField(fields, "quote_token"),
			quoteAmount,
			uint8Field(fields, "kind"),
			bytesField(fields, "metadata"),
		}, nil
	case "Ack":
		tag, err := uint256Field(fields, "tag")
		if err != nil {
			return nil, err
		}
		return []any{tag, bytesField(fields, "inner_ack")}, nil
	case "BatchAck":
		arr := fields["acknowledgements"].MustArray()
		acks := make([]any, len(arr))
		for i, elem := range arr {
			acks[i] = mustHex0x(elem.MustString())
		}
		return []any{acks}, nil
	case "TokenOrderAck":
		fillType, err := uint256Field(fields, "fill_type")
		if err != nil {
			return nil, err
		}
		return []any{fillType, bytesField(fields, "market_maker")}, nil
	default:
		return nil, abi.ErrUnsupportedType
	}
}

func encodeTypedFromFields(typeName string, node *json.Node) ([]byte, error) {
	fields := node.MustObject()
	switch typeName {
	case "Instruction":
		return EncodeInstruction(instructionFromFields(fields))
	case "Call":
		return EncodeCall(Call{
			Sender:           bytesField(fields, "sender"),
			Eureka:           fields["eureka"].MustBool(),
			ContractAddress:  bytesField(fields, "contract_address"),
			ContractCalldata: bytesField(fields, "contract_calldata"),
		})
	case "ZkgmPacket":
		salt, err := bytes32Field(fields, "salt")
		if err != nil {
			return nil, err
		}
		path, err := uint256Field(fields, "path")
		if err != nil {
			return nil, err
		}
		return EncodeZkgmPacket(ZkgmPacket{
			Salt:        salt,
			Path:        path,
			Instruction: instructionFromFields(fields["instruction"].MustObject()),
		})
	case "Forward":
		path, err := uint256Field(fields, "path")
		if err != nil {
			return nil, err
		}
		timeoutHeight, err := uint64Field(fields, "timeout_height")
		if err != nil {
			return nil, err
		}
		timeoutTimestamp, err := uint64Field(fields, "timeout_timestamp")
		if err != nil {
			return nil, err
		}
		return EncodeForward(Forward{
			Path:             path,
			TimeoutHeight:    timeoutHeight,
			TimeoutTimestamp: timeoutTimestamp,
			Instruction:      instructionFromFields(fields["instruction"].MustObject()),
		})
	case "Batch":
		arr := fields["instructions"].MustArray()
		instructions := make([]Instruction, len(arr))
		for i, elem := range arr {
			instructions[i] = instructionFromFields(elem.MustObject())
		}
		return EncodeBatch(Batch{Instructions: instructions})
	case "TokenOrderV1":
		baseAmount, err := uint256Field(fields, "base_amount")
		if err != nil {
			return nil, err
		}
		basePath, err := uint256Field(fields, "base_token_path")
		if err != nil {
			return nil, err
		}
		quoteAmount, err := uint256Field(fields, "quote_amount")
		if err != nil {
			return nil, err
		}
		return EncodeTokenOrderV1(TokenOrderV1{
			Sender:            bytesField(fields, "sender"),
			Receiver:          bytesField(fields, "receiver"),
			BaseToken:         bytesField(fields, "base_token"),
			BaseAmount:        baseAmount,
			BaseTokenSymbol:   fields["base_token_symbol"].MustString(),
			BaseTokenName:     fields["base_token_name"].MustString(),
			BaseTokenDecimals: uint8Field(fields, "base_token_decimals"),
			BaseTokenPath:     basePath,
			QuoteToken:        bytesField(fields, "quote_token"),
			QuoteAmount:       quoteAmount,
		})
	case "TokenOrderV2":
		baseAmount, err := uint256Field(fields, "base_amount")
		if err != nil {
			return nil, err
		}
		quoteAmount, err := uint256Field(fields, "quote_amount")
		if err != nil {
			return nil, err
		}
		return EncodeTokenOrderV2(TokenOrderV2{
			Sender:      bytesField(fields, "sender"),
			Receiver:    bytesField(fields, "receiver"),
			BaseToken:   bytesField(fields, "base_token"),
			BaseAmount:  baseAmount,
			QuoteToken:  bytesField(fields, "quote_token"),
			QuoteAmount: quoteAmount,
			Kind:        uint8Field(fields, "kind"),
			Metadata:    bytesField(fields, "metadata"),
		})
	case "Ack":
		tag, err := uint256Field(fields, "tag")
		if err != nil {
			return nil, err
		}
		return EncodeAck(Ack{Tag: tag, InnerAck: bytesField(fields, "inner_ack")})
	case "BatchAck":
		arr := fields["acknowledgements"].MustArray()
		acks := make([][]byte, len(arr))
		for i, elem := range arr {
			acks[i] = mustHex0x(elem.MustString())
		}
		return EncodeBatchAck(BatchAck{Acknowledgements: acks})
	case "TokenOrderAck":
		fillType, err := uint256Field(fields, "fill_type")
		if err != nil {
			return nil, err
		}
		return EncodeTokenOrderAck(TokenOrderAck{FillType: fillType, MarketMaker: bytesField(fields, "market_maker")})
	default:
		return nil, abi.ErrUnsupportedType
	}
}

func assertTypedDecodeRoundTrip(t *testing.T, typeName string, data []byte) {
	t.Helper()
	var out []byte
	var err error
	switch typeName {
	case "Instruction":
		var v Instruction
		v, err = DecodeInstruction(data)
		if err == nil {
			out, err = EncodeInstruction(v)
		}
	case "Call":
		var v Call
		v, err = DecodeCall(data)
		if err == nil {
			out, err = EncodeCall(v)
		}
	case "ZkgmPacket":
		var v ZkgmPacket
		v, err = DecodeZkgmPacket(data)
		if err == nil {
			out, err = EncodeZkgmPacket(v)
		}
	case "Forward":
		var v Forward
		v, err = DecodeForward(data)
		if err == nil {
			out, err = EncodeForward(v)
		}
	case "Batch":
		var v Batch
		v, err = DecodeBatch(data)
		if err == nil {
			out, err = EncodeBatch(v)
		}
	case "TokenOrderV1":
		var v TokenOrderV1
		v, err = DecodeTokenOrderV1(data)
		if err == nil {
			out, err = EncodeTokenOrderV1(v)
		}
	case "TokenOrderV2":
		var v TokenOrderV2
		v, err = DecodeTokenOrderV2(data)
		if err == nil {
			out, err = EncodeTokenOrderV2(v)
		}
	case "Ack":
		var v Ack
		v, err = DecodeAck(data)
		if err == nil {
			out, err = EncodeAck(v)
		}
	case "BatchAck":
		var v BatchAck
		v, err = DecodeBatchAck(data)
		if err == nil {
			out, err = EncodeBatchAck(v)
		}
	case "TokenOrderAck":
		var v TokenOrderAck
		v, err = DecodeTokenOrderAck(data)
		if err == nil {
			out, err = EncodeTokenOrderAck(v)
		}
	default:
		t.Fatalf("typed round-trip: unsupported type %s", typeName)
	}
	if err != nil {
		t.Fatalf("typed round-trip %s: %v", typeName, err)
	}
	if !bytes.Equal(out, data) {
		t.Fatalf("typed round-trip %s changed bytes\n got %s\nwant %s", typeName, hex.EncodeToString(out), hex.EncodeToString(data))
	}
}

func instructionFromFields(fields map[string]*json.Node) Instruction {
	return Instruction{
		Version: uint8Field(fields, "version"),
		Opcode:  uint8Field(fields, "opcode"),
		Operand: bytesField(fields, "operand"),
	}
}

func fixtureInstructionValues(fields map[string]*json.Node) []any {
	return instructionValues(instructionFromFields(fields))
}

func bytesField(fields map[string]*json.Node, key string) []byte {
	return mustHex0x(fields[key].MustString())
}

func bytes32Field(fields map[string]*json.Node, key string) ([32]byte, error) {
	bz := bytesField(fields, key)
	var out [32]byte
	if len(bz) != 32 {
		return out, abi.ErrInvalidValue
	}
	copy(out[:], bz)
	return out, nil
}

func uint8Field(fields map[string]*json.Node, key string) uint8 {
	return uint8(fields[key].MustNumeric())
}

func uint64Field(fields map[string]*json.Node, key string) (uint64, error) {
	node := fields[key]
	if node.IsString() {
		return strconv.ParseUint(node.MustString(), 10, 64)
	}
	return uint64(node.MustNumeric()), nil
}

func uint256Field(fields map[string]*json.Node, key string) (*u256.Uint, error) {
	node := fields[key]
	if node.IsString() {
		return u256.FromDecimal(node.MustString())
	}
	return u256.NewUint(uint64(node.MustNumeric())), nil
}

func mustHex(s string) []byte {
	bz, err := hex.DecodeString(s)
	if err != nil {
		panic(err)
	}
	return bz
}

func mustHex0x(s string) []byte {
	if len(s) < 2 || s[0:2] != "0x" {
		panic("hex string missing 0x prefix")
	}
	return mustHex(s[2:])
}

func mustEncodeForward(f Forward) []byte {
	data, err := EncodeForward(f)
	if err != nil {
		panic(err)
	}
	return data
}
