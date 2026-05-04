package zkgm

import (
	"gno.land/p/gnoswap/encoding/abi"
	u256 "gno.land/p/gnoswap/uint256"
)

var InstructionSchema = abi.Schema{Fields: []abi.Field{
	{Type: abi.TypeUint8},
	{Type: abi.TypeUint8},
	{Type: abi.TypeBytes},
}}

var CallSchema = abi.Schema{Fields: []abi.Field{
	{Type: abi.TypeBytes},
	{Type: abi.TypeBool},
	{Type: abi.TypeBytes},
	{Type: abi.TypeBytes},
}}

var ZkgmPacketSchema = abi.Schema{Fields: []abi.Field{
	{Type: abi.TypeBytes32},
	{Type: abi.TypeUint256},
	{Type: abi.TypeStruct, Sub: &InstructionSchema},
}}

var ForwardSchema = abi.Schema{Fields: []abi.Field{
	{Type: abi.TypeUint256},
	{Type: abi.TypeUint64},
	{Type: abi.TypeUint64},
	{Type: abi.TypeStruct, Sub: &InstructionSchema},
}}

var BatchSchema = abi.Schema{Fields: []abi.Field{
	{Type: abi.TypeArray, Elem: &abi.Field{Type: abi.TypeStruct, Sub: &InstructionSchema}},
}}

var TokenOrderV2Schema = abi.Schema{Fields: []abi.Field{
	{Type: abi.TypeBytes},
	{Type: abi.TypeBytes},
	{Type: abi.TypeBytes},
	{Type: abi.TypeUint256},
	{Type: abi.TypeBytes},
	{Type: abi.TypeUint256},
	{Type: abi.TypeUint8},
	{Type: abi.TypeBytes},
}}

var TokenOrderV1Schema = abi.Schema{Fields: []abi.Field{
	{Type: abi.TypeBytes},
	{Type: abi.TypeBytes},
	{Type: abi.TypeBytes},
	{Type: abi.TypeUint256},
	{Type: abi.TypeString},
	{Type: abi.TypeString},
	{Type: abi.TypeUint8},
	{Type: abi.TypeUint256},
	{Type: abi.TypeBytes},
	{Type: abi.TypeUint256},
}}

var AckSchema = abi.Schema{Fields: []abi.Field{
	{Type: abi.TypeUint256},
	{Type: abi.TypeBytes},
}}

var BatchAckSchema = abi.Schema{Fields: []abi.Field{
	{Type: abi.TypeArray, Elem: &abi.Field{Type: abi.TypeBytes}},
}}

var TokenOrderAckSchema = abi.Schema{Fields: []abi.Field{
	{Type: abi.TypeUint256},
	{Type: abi.TypeBytes},
}}

var TokenMetadataSchema = abi.Schema{Fields: []abi.Field{
	{Type: abi.TypeBytes},
	{Type: abi.TypeBytes},
}}

var SolverMetadataSchema = abi.Schema{Fields: []abi.Field{
	{Type: abi.TypeBytes},
	{Type: abi.TypeBytes},
}}

func EncodeZkgmPacket(p ZkgmPacket) ([]byte, error) {
	return abi.Encode(ZkgmPacketSchema, []any{
		p.Salt,
		p.Path,
		instructionValues(p.Instruction),
	})
}

func DecodeZkgmPacket(data []byte) (ZkgmPacket, error) {
	out, err := abi.Decode(ZkgmPacketSchema, data)
	if err != nil {
		return ZkgmPacket{}, err
	}
	return ZkgmPacket{
		Salt:        out[0].([32]byte),
		Path:        out[1].(*u256.Uint),
		Instruction: instructionFromValues(out[2].([]any)),
	}, nil
}

func EncodeInstruction(ins Instruction) ([]byte, error) {
	return abi.Encode(InstructionSchema, instructionValues(ins))
}

func DecodeInstruction(data []byte) (Instruction, error) {
	out, err := abi.Decode(InstructionSchema, data)
	if err != nil {
		return Instruction{}, err
	}
	return instructionFromValues(out), nil
}

func EncodeForward(f Forward) ([]byte, error) {
	return abi.Encode(ForwardSchema, []any{
		f.Path,
		f.TimeoutHeight,
		f.TimeoutTimestamp,
		instructionValues(f.Instruction),
	})
}

func DecodeForward(data []byte) (Forward, error) {
	out, err := abi.Decode(ForwardSchema, data)
	if err != nil {
		return Forward{}, err
	}
	return Forward{
		Path:             out[0].(*u256.Uint),
		TimeoutHeight:    out[1].(uint64),
		TimeoutTimestamp: out[2].(uint64),
		Instruction:      instructionFromValues(out[3].([]any)),
	}, nil
}

func EncodeCall(c Call) ([]byte, error) {
	return abi.Encode(CallSchema, []any{
		c.Sender,
		c.Eureka,
		c.ContractAddress,
		c.ContractCalldata,
	})
}

func DecodeCall(data []byte) (Call, error) {
	out, err := abi.Decode(CallSchema, data)
	if err != nil {
		return Call{}, err
	}
	return Call{
		Sender:           out[0].([]byte),
		Eureka:           out[1].(bool),
		ContractAddress:  out[2].([]byte),
		ContractCalldata: out[3].([]byte),
	}, nil
}

func EncodeBatch(b Batch) ([]byte, error) {
	items := make([]any, len(b.Instructions))
	for i, ins := range b.Instructions {
		items[i] = instructionValues(ins)
	}
	return abi.Encode(BatchSchema, []any{items})
}

func DecodeBatch(data []byte) (Batch, error) {
	out, err := abi.Decode(BatchSchema, data)
	if err != nil {
		return Batch{}, err
	}
	items := out[0].([]any)
	instructions := make([]Instruction, len(items))
	for i, item := range items {
		instructions[i] = instructionFromValues(item.([]any))
	}
	return Batch{Instructions: instructions}, nil
}

func EncodeTokenOrderV1(o TokenOrderV1) ([]byte, error) {
	return abi.Encode(TokenOrderV1Schema, []any{
		o.Sender,
		o.Receiver,
		o.BaseToken,
		o.BaseAmount,
		o.BaseTokenSymbol,
		o.BaseTokenName,
		o.BaseTokenDecimals,
		o.BaseTokenPath,
		o.QuoteToken,
		o.QuoteAmount,
	})
}

func DecodeTokenOrderV1(data []byte) (TokenOrderV1, error) {
	out, err := abi.Decode(TokenOrderV1Schema, data)
	if err != nil {
		return TokenOrderV1{}, err
	}
	return TokenOrderV1{
		Sender:            out[0].([]byte),
		Receiver:          out[1].([]byte),
		BaseToken:         out[2].([]byte),
		BaseAmount:        out[3].(*u256.Uint),
		BaseTokenSymbol:   out[4].(string),
		BaseTokenName:     out[5].(string),
		BaseTokenDecimals: out[6].(uint8),
		BaseTokenPath:     out[7].(*u256.Uint),
		QuoteToken:        out[8].([]byte),
		QuoteAmount:       out[9].(*u256.Uint),
	}, nil
}

func EncodeTokenOrderV2(o TokenOrderV2) ([]byte, error) {
	return abi.Encode(TokenOrderV2Schema, []any{
		o.Sender,
		o.Receiver,
		o.BaseToken,
		o.BaseAmount,
		o.QuoteToken,
		o.QuoteAmount,
		o.Kind,
		o.Metadata,
	})
}

func DecodeTokenOrderV2(data []byte) (TokenOrderV2, error) {
	out, err := abi.Decode(TokenOrderV2Schema, data)
	if err != nil {
		return TokenOrderV2{}, err
	}
	return TokenOrderV2{
		Sender:      out[0].([]byte),
		Receiver:    out[1].([]byte),
		BaseToken:   out[2].([]byte),
		BaseAmount:  out[3].(*u256.Uint),
		QuoteToken:  out[4].([]byte),
		QuoteAmount: out[5].(*u256.Uint),
		Kind:        out[6].(uint8),
		Metadata:    out[7].([]byte),
	}, nil
}

func EncodeTokenMetadata(m TokenMetadata) ([]byte, error) {
	return abi.Encode(TokenMetadataSchema, []any{
		m.Implementation,
		m.Initializer,
	})
}

func DecodeTokenMetadata(data []byte) (TokenMetadata, error) {
	out, err := abi.Decode(TokenMetadataSchema, data)
	if err != nil {
		return TokenMetadata{}, err
	}
	return TokenMetadata{
		Implementation: out[0].([]byte),
		Initializer:    out[1].([]byte),
	}, nil
}

func EncodeSolverMetadata(m SolverMetadata) ([]byte, error) {
	return abi.Encode(SolverMetadataSchema, []any{
		m.SolverAddress,
		m.Metadata,
	})
}

func DecodeSolverMetadata(data []byte) (SolverMetadata, error) {
	out, err := abi.Decode(SolverMetadataSchema, data)
	if err != nil {
		return SolverMetadata{}, err
	}
	return SolverMetadata{
		SolverAddress: out[0].([]byte),
		Metadata:      out[1].([]byte),
	}, nil
}

func EncodeAck(a Ack) ([]byte, error) {
	return abi.Encode(AckSchema, []any{
		a.Tag,
		a.InnerAck,
	})
}

func DecodeAck(data []byte) (Ack, error) {
	out, err := abi.Decode(AckSchema, data)
	if err != nil {
		return Ack{}, err
	}
	return Ack{
		Tag:      out[0].(*u256.Uint),
		InnerAck: out[1].([]byte),
	}, nil
}

func EncodeBatchAck(a BatchAck) ([]byte, error) {
	items := make([]any, len(a.Acknowledgements))
	for i, ack := range a.Acknowledgements {
		items[i] = ack
	}
	return abi.Encode(BatchAckSchema, []any{items})
}

func DecodeBatchAck(data []byte) (BatchAck, error) {
	out, err := abi.Decode(BatchAckSchema, data)
	if err != nil {
		return BatchAck{}, err
	}
	items := out[0].([]any)
	acks := make([][]byte, len(items))
	for i, item := range items {
		acks[i] = item.([]byte)
	}
	return BatchAck{Acknowledgements: acks}, nil
}

func EncodeTokenOrderAck(a TokenOrderAck) ([]byte, error) {
	return abi.Encode(TokenOrderAckSchema, []any{
		a.FillType,
		a.MarketMaker,
	})
}

func DecodeTokenOrderAck(data []byte) (TokenOrderAck, error) {
	out, err := abi.Decode(TokenOrderAckSchema, data)
	if err != nil {
		return TokenOrderAck{}, err
	}
	return TokenOrderAck{
		FillType:    out[0].(*u256.Uint),
		MarketMaker: out[1].([]byte),
	}, nil
}

func instructionValues(ins Instruction) []any {
	return []any{ins.Version, ins.Opcode, ins.Operand}
}

func instructionFromValues(values []any) Instruction {
	return Instruction{
		Version: values[0].(uint8),
		Opcode:  values[1].(uint8),
		Operand: values[2].([]byte),
	}
}
