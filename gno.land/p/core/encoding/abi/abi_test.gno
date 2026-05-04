package abi

import (
	"encoding/hex"
	"strconv"
	"testing"

	"gno.land/p/onbloc/json"

	u256 "gno.land/p/gnoswap/uint256"
)

var instructionSchema = Schema{Fields: []Field{
	{Type: TypeUint8},
	{Type: TypeUint8},
	{Type: TypeBytes},
}}

var callSchema = Schema{Fields: []Field{
	{Type: TypeBytes},
	{Type: TypeBool},
	{Type: TypeBytes},
	{Type: TypeBytes},
}}

var zkgmPacketSchema = Schema{Fields: []Field{
	{Type: TypeBytes32},
	{Type: TypeUint256},
	{Type: TypeStruct, Sub: &instructionSchema},
}}

var forwardSchema = Schema{Fields: []Field{
	{Type: TypeUint256},
	{Type: TypeUint64},
	{Type: TypeUint64},
	{Type: TypeStruct, Sub: &instructionSchema},
}}

var batchSchema = Schema{Fields: []Field{
	{Type: TypeArray, Elem: &Field{Type: TypeStruct, Sub: &instructionSchema}},
}}

var batchAckSchema = Schema{Fields: []Field{
	{Type: TypeArray, Elem: &Field{Type: TypeBytes}},
}}

var tokenOrderV2Schema = Schema{Fields: []Field{
	{Type: TypeBytes},
	{Type: TypeBytes},
	{Type: TypeBytes},
	{Type: TypeUint256},
	{Type: TypeBytes},
	{Type: TypeUint256},
	{Type: TypeUint8},
	{Type: TypeBytes},
}}

var tokenOrderV1Schema = Schema{Fields: []Field{
	{Type: TypeBytes},
	{Type: TypeBytes},
	{Type: TypeBytes},
	{Type: TypeUint256},
	{Type: TypeString},
	{Type: TypeString},
	{Type: TypeUint8},
	{Type: TypeUint256},
	{Type: TypeBytes},
	{Type: TypeUint256},
}}

var ackSchema = Schema{Fields: []Field{
	{Type: TypeUint256},
	{Type: TypeBytes},
}}

var tokenOrderAckSchema = Schema{Fields: []Field{
	{Type: TypeUint256},
	{Type: TypeBytes},
}}

func TestEncodeKnownVectors(t *testing.T) {
	assertEncodeHex(t, "Instruction_short_operand", instructionSchema, []any{
		uint8(2),
		uint8(3),
		mustHex("aabbcc"),
	}, "0000000000000000000000000000000000000000000000000000000000000002"+
		"0000000000000000000000000000000000000000000000000000000000000003"+
		"0000000000000000000000000000000000000000000000000000000000000060"+
		"0000000000000000000000000000000000000000000000000000000000000003"+
		"aabbcc0000000000000000000000000000000000000000000000000000000000")

	assertEncodeHex(t, "Call_basic", callSchema, []any{
		[]byte("alice"),
		true,
		[]byte("bobcontract"),
		mustHex("cafe"),
	}, "0000000000000000000000000000000000000000000000000000000000000080"+
		"0000000000000000000000000000000000000000000000000000000000000001"+
		"00000000000000000000000000000000000000000000000000000000000000c0"+
		"0000000000000000000000000000000000000000000000000000000000000100"+
		"0000000000000000000000000000000000000000000000000000000000000005"+
		"616c696365000000000000000000000000000000000000000000000000000000"+
		"000000000000000000000000000000000000000000000000000000000000000b"+
		"626f62636f6e7472616374000000000000000000000000000000000000000000"+
		"0000000000000000000000000000000000000000000000000000000000000002"+
		"cafe000000000000000000000000000000000000000000000000000000000000")

	var salt [32]byte
	for i := range salt {
		salt[i] = 0xab
	}
	assertEncodeHex(t, "ZkgmPacket_with_short_call_operand", zkgmPacketSchema, []any{
		salt,
		u256.NewUint(7),
		[]any{uint8(0), uint8(1), mustHex("0102")},
	}, "abababababababababababababababababababababababababababababababab"+
		"0000000000000000000000000000000000000000000000000000000000000007"+
		"0000000000000000000000000000000000000000000000000000000000000060"+
		"0000000000000000000000000000000000000000000000000000000000000000"+
		"0000000000000000000000000000000000000000000000000000000000000001"+
		"0000000000000000000000000000000000000000000000000000000000000060"+
		"0000000000000000000000000000000000000000000000000000000000000002"+
		"0102000000000000000000000000000000000000000000000000000000000000")
}

func TestDecodeKnownVectors(t *testing.T) {
	out, err := Decode(instructionSchema, mustHex("0000000000000000000000000000000000000000000000000000000000000002"+
		"0000000000000000000000000000000000000000000000000000000000000003"+
		"0000000000000000000000000000000000000000000000000000000000000060"+
		"0000000000000000000000000000000000000000000000000000000000000003"+
		"aabbcc0000000000000000000000000000000000000000000000000000000000"))
	if err != nil {
		t.Fatalf("Decode Instruction: %v", err)
	}
	if out[0].(uint8) != 2 || out[1].(uint8) != 3 || hex.EncodeToString(out[2].([]byte)) != "aabbcc" {
		t.Fatalf("decoded instruction mismatch")
	}

	call, err := Decode(callSchema, mustHex("0000000000000000000000000000000000000000000000000000000000000080"+
		"0000000000000000000000000000000000000000000000000000000000000001"+
		"00000000000000000000000000000000000000000000000000000000000000c0"+
		"0000000000000000000000000000000000000000000000000000000000000100"+
		"0000000000000000000000000000000000000000000000000000000000000005"+
		"616c696365000000000000000000000000000000000000000000000000000000"+
		"000000000000000000000000000000000000000000000000000000000000000b"+
		"626f62636f6e7472616374000000000000000000000000000000000000000000"+
		"0000000000000000000000000000000000000000000000000000000000000002"+
		"cafe000000000000000000000000000000000000000000000000000000000000"))
	if err != nil {
		t.Fatalf("Decode Call: %v", err)
	}
	if string(call[0].([]byte)) != "alice" || call[1].(bool) != true || string(call[2].([]byte)) != "bobcontract" || hex.EncodeToString(call[3].([]byte)) != "cafe" {
		t.Fatalf("decoded call mismatch")
	}
}

func TestRoundTripDynamicArrays(t *testing.T) {
	batchValues := []any{
		[]any{
			[]any{uint8(0), uint8(1), mustHex("0102")},
			[]any{uint8(2), uint8(3), mustHex("aabbcc")},
			[]any{uint8(0), uint8(2), []byte{}},
		},
	}
	bz, err := Encode(batchSchema, batchValues)
	if err != nil {
		t.Fatalf("Encode Batch: %v", err)
	}
	decoded, err := Decode(batchSchema, bz)
	if err != nil {
		t.Fatalf("Decode Batch: %v", err)
	}
	items := decoded[0].([]any)
	if len(items) != 3 {
		t.Fatalf("batch length: got %d want 3", len(items))
	}
	second := items[1].([]any)
	if second[0].(uint8) != 2 || second[1].(uint8) != 3 || hex.EncodeToString(second[2].([]byte)) != "aabbcc" {
		t.Fatalf("decoded batch element mismatch")
	}

	acks := []any{[]any{mustHex("dead"), []byte{}, mustHex("cafe01")}}
	bz, err = Encode(batchAckSchema, acks)
	if err != nil {
		t.Fatalf("Encode BatchAck: %v", err)
	}
	decoded, err = Decode(batchAckSchema, bz)
	if err != nil {
		t.Fatalf("Decode BatchAck: %v", err)
	}
	ackItems := decoded[0].([]any)
	if len(ackItems) != 3 || hex.EncodeToString(ackItems[2].([]byte)) != "cafe01" {
		t.Fatalf("decoded batch ack mismatch")
	}
}

func TestRoundTripForwardAndTokenOrder(t *testing.T) {
	callOperand, err := Encode(callSchema, []any{
		[]byte("sender"),
		true,
		[]byte("contract"),
		mustHex("cafe"),
	})
	if err != nil {
		t.Fatalf("Encode Call operand: %v", err)
	}

	forwardValues := []any{
		u256.NewUint(0x12345),
		uint64(100),
		uint64(1700000000000000000),
		[]any{uint8(0), uint8(1), callOperand},
	}
	bz, err := Encode(forwardSchema, forwardValues)
	if err != nil {
		t.Fatalf("Encode Forward: %v", err)
	}
	decoded, err := Decode(forwardSchema, bz)
	if err != nil {
		t.Fatalf("Decode Forward: %v", err)
	}
	if decoded[0].(*u256.Uint).ToString() != "74565" || decoded[1].(uint64) != 100 {
		t.Fatalf("decoded forward scalar mismatch")
	}
	ins := decoded[3].([]any)
	if ins[0].(uint8) != 0 || ins[1].(uint8) != 1 || hex.EncodeToString(ins[2].([]byte)) != hex.EncodeToString(callOperand) {
		t.Fatalf("decoded forward instruction mismatch")
	}

	orderValues := []any{
		[]byte("alice"),
		[]byte("bob"),
		[]byte("unionToken"),
		u256.NewUint(1000000),
		[]byte("uatom"),
		u256.NewUint(2500000),
		uint8(1),
		[]byte{},
	}
	bz, err = Encode(tokenOrderV2Schema, orderValues)
	if err != nil {
		t.Fatalf("Encode TokenOrderV2: %v", err)
	}
	decoded, err = Decode(tokenOrderV2Schema, bz)
	if err != nil {
		t.Fatalf("Decode TokenOrderV2: %v", err)
	}
	if string(decoded[0].([]byte)) != "alice" || decoded[3].(*u256.Uint).ToString() != "1000000" || decoded[6].(uint8) != 1 {
		t.Fatalf("decoded token order mismatch")
	}
}

func TestRejectMalformedData(t *testing.T) {
	if _, err := Decode(instructionSchema, []byte{1, 2, 3}); err == nil {
		t.Fatalf("expected invalid data error")
	}

	badBool := make([]byte, 32)
	badBool[31] = 2
	if _, err := Decode(Schema{Fields: []Field{{Type: TypeBool}}}, badBool); err == nil {
		t.Fatalf("expected invalid bool error")
	}
}

func TestJSONVectorLoaderShape(t *testing.T) {
	root, err := json.Unmarshal([]byte(`[{"name":"Instruction_short_operand","type":"Instruction","fields":{"version":2,"opcode":3,"operand":"0xaabbcc"},"abi_hex":"0x1234"},{"name":"RealPacket_msg_rs_259","type":"Instruction","fields":null,"abi_hex":"0xabcd"}]`))
	if err != nil {
		t.Fatalf("Unmarshal vector JSON: %v", err)
	}
	vectors := root.MustArray()
	if len(vectors) != 2 {
		t.Fatalf("vector count: got %d want 2", len(vectors))
	}

	first := vectors[0].MustObject()
	if first["name"].MustString() != "Instruction_short_operand" || first["type"].MustString() != "Instruction" {
		t.Fatalf("vector metadata mismatch")
	}
	fields := first["fields"].MustObject()
	if fields["operand"].MustString() != "0xaabbcc" {
		t.Fatalf("vector fields mismatch")
	}
	if !vectors[1].MustObject()["fields"].IsNull() {
		t.Fatalf("decode-only vector should have null fields")
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
		vector := vectorNode.MustObject()
		name := vector["name"].MustString()
		typeName := vector["type"].MustString()
		abiHex := vector["abi_hex"].MustString()
		abiBytes := mustHex0x(abiHex)
		schema, ok := schemaByType(typeName)
		if !ok {
			t.Fatalf("%s: unsupported fixture type %s", name, typeName)
		}

		decoded, err := Decode(schema, abiBytes)
		if err != nil {
			t.Fatalf("%s Decode: %v", name, err)
		}
		decodedBytes, err := Encode(schema, decoded)
		if err != nil {
			t.Fatalf("%s Encode(decoded): %v", name, err)
		}
		if hex.EncodeToString(decodedBytes) != hex.EncodeToString(abiBytes) {
			t.Fatalf("%s decode round-trip changed bytes", name)
		}

		fields := vector["fields"]
		if fields.IsNull() {
			if name != "RealPacket_msg_rs_259" {
				t.Fatalf("%s: only real packet fixture may omit fields", name)
			}
			if decoded[0].(uint8) != 0 || decoded[1].(uint8) != 2 {
				t.Fatalf("%s sentinel mismatch", name)
			}
			continue
		}

		values, err := valuesFromFields(typeName, fields)
		if err != nil {
			t.Fatalf("%s valuesFromFields: %v", name, err)
		}
		encoded, err := Encode(schema, values)
		if err != nil {
			t.Fatalf("%s Encode(fields): %v", name, err)
		}
		if hex.EncodeToString(encoded) != hex.EncodeToString(abiBytes) {
			t.Fatalf("%s\n got %s\nwant %s", name, hex.EncodeToString(encoded), hex.EncodeToString(abiBytes))
		}
	}
}

func TestDecodeDepthLimit(t *testing.T) {
	data := mustHex("0000000000000000000000000000000000000000000000000000000000000020" +
		"0000000000000000000000000000000000000000000000000000000000000000")
	d := decoder{data: data, maxDepth: 0}
	_, err := d.tupleAt([]Field{{Type: TypeBytes}}, 0, len(data), 0)
	if err != ErrDepthLimit {
		t.Fatalf("got %v want ErrDepthLimit", err)
	}
}

func assertEncodeHex(t *testing.T, name string, schema Schema, values []any, want string) {
	got, err := Encode(schema, values)
	if err != nil {
		t.Fatalf("%s Encode: %v", name, err)
	}
	if hex.EncodeToString(got) != want {
		t.Fatalf("%s\n got %s\nwant %s", name, hex.EncodeToString(got), want)
	}

	decoded, err := Decode(schema, got)
	if err != nil {
		t.Fatalf("%s Decode(encoded): %v", name, err)
	}
	encodedAgain, err := Encode(schema, decoded)
	if err != nil {
		t.Fatalf("%s Encode(decoded): %v", name, err)
	}
	if hex.EncodeToString(encodedAgain) != want {
		t.Fatalf("%s round-trip changed bytes", name)
	}
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

func schemaByType(typeName string) (Schema, bool) {
	switch typeName {
	case "Instruction":
		return instructionSchema, true
	case "Call":
		return callSchema, true
	case "ZkgmPacket":
		return zkgmPacketSchema, true
	case "Forward":
		return forwardSchema, true
	case "Batch":
		return batchSchema, true
	case "TokenOrderV1":
		return tokenOrderV1Schema, true
	case "TokenOrderV2":
		return tokenOrderV2Schema, true
	case "Ack":
		return ackSchema, true
	case "BatchAck":
		return batchAckSchema, true
	case "TokenOrderAck":
		return tokenOrderAckSchema, true
	default:
		return Schema{}, false
	}
}

func valuesFromFields(typeName string, node *json.Node) ([]any, error) {
	fields := node.MustObject()
	switch typeName {
	case "Instruction":
		return instructionValues(fields), nil
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
			instructionValues(fields["instruction"].MustObject()),
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
			instructionValues(fields["instruction"].MustObject()),
		}, nil
	case "Batch":
		arr := fields["instructions"].MustArray()
		instructions := make([]any, len(arr))
		for i, elem := range arr {
			instructions[i] = instructionValues(elem.MustObject())
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
		return nil, ErrUnsupportedType
	}
}

func instructionValues(fields map[string]*json.Node) []any {
	return []any{
		uint8Field(fields, "version"),
		uint8Field(fields, "opcode"),
		bytesField(fields, "operand"),
	}
}

func bytesField(fields map[string]*json.Node, key string) []byte {
	return mustHex0x(fields[key].MustString())
}

func bytes32Field(fields map[string]*json.Node, key string) ([32]byte, error) {
	bz := bytesField(fields, key)
	var out [32]byte
	if len(bz) != 32 {
		return out, ErrInvalidValue
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
