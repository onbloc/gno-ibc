package zkgm

import (
	"bytes"
	"encoding/hex"
	"strconv"
	"testing"

	"gno.land/p/gnoswap/encoding/abi"
	"gno.land/p/onbloc/json"

	u256 "gno.land/p/gnoswap/uint256"
)

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
			continue
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
	}
}

func TestMetadataWrapperRoundTrip(t *testing.T) {
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
