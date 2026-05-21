// Command check-zkgm-tokenorder-vectors validates committed TokenOrderV2
// payloads captured from Gno -> Union integration work without network calls.
package main

import (
	"encoding/hex"
	"encoding/json"
	"fmt"
	"math/big"
	"os"
	"path/filepath"
	"runtime"
	"strings"
)

type fixture struct {
	Vectors []vector `json:"vectors"`
}

type vector struct {
	Name       string            `json:"name"`
	Source     string            `json:"source"`
	OperandHex string            `json:"operand_hex"`
	Expected   map[string]string `json:"expected"`
}

type decodedTokenOrder struct {
	Sender      string
	Receiver    string
	BaseToken   string
	BaseAmount  string
	QuoteToken  string
	QuoteAmount string
	Kind        string
	Metadata    []byte
}

type decodedMetadata struct {
	Implementation string
	Initializer    []byte
}

type decodedInitializer struct {
	Selector  string
	Authority string
	Zkgm      string
	Name      string
	Symbol    string
	Decimals  string
}

func main() {
	fx := mustReadFixture()
	if len(fx.Vectors) == 0 {
		fail("no vectors")
	}

	for _, v := range fx.Vectors {
		if v.Name == "" {
			fail("vector has empty name")
		}
		order := decodeTokenOrderV2(v.OperandHex)
		expect(v, "sender_hex", order.Sender)
		expect(v, "receiver_hex", order.Receiver)
		expect(v, "base_token_hex", order.BaseToken)
		expect(v, "base_amount", order.BaseAmount)
		expect(v, "quote_token_hex", order.QuoteToken)
		expect(v, "quote_amount", order.QuoteAmount)
		expect(v, "kind", order.Kind)

		if want, ok := v.Expected["metadata_hex"]; ok {
			requireEqual(v.Name+" metadata_hex", hex0x(order.Metadata), normalizedHex(want))
		}
		if _, ok := v.Expected["metadata_implementation_hex"]; ok {
			meta := decodeTokenMetadata(order.Metadata)
			expect(v, "metadata_implementation_hex", meta.Implementation)
			init := decodeInitializer(meta.Initializer)
			expect(v, "initializer_selector", init.Selector)
			expect(v, "initializer_authority", init.Authority)
			expect(v, "initializer_zkgm", init.Zkgm)
			expect(v, "initializer_name", init.Name)
			expect(v, "initializer_symbol", init.Symbol)
			expect(v, "initializer_decimals", init.Decimals)
		}
	}

	fmt.Println("PASS: ZKGM TokenOrder vectors")
}

func decodeTokenOrderV2(inputHex string) decodedTokenOrder {
	b := mustHex(inputHex)
	if len(b) < 32*8 {
		fail("TokenOrderV2 operand too short: %d bytes", len(b))
	}
	return decodedTokenOrder{
		Sender:      hex0x(dynamicBytesField("sender", b, wordUint(b, 0))),
		Receiver:    hex0x(dynamicBytesField("receiver", b, wordUint(b, 32))),
		BaseToken:   hex0x(dynamicBytesField("base token", b, wordUint(b, 64))),
		BaseAmount:  wordBig(b, 96).String(),
		QuoteToken:  hex0x(dynamicBytesField("quote token", b, wordUint(b, 128))),
		QuoteAmount: wordBig(b, 160).String(),
		Kind:        fmt.Sprint(wordUint(b, 192)),
		Metadata:    dynamicBytesField("metadata", b, wordUint(b, 224)),
	}
}

func decodeTokenMetadata(b []byte) decodedMetadata {
	if len(b) < 64 {
		fail("TokenMetadata too short: %d bytes", len(b))
	}
	return decodedMetadata{
		Implementation: hex0x(dynamicBytes(b, wordUint(b, 0))),
		Initializer:    dynamicBytes(b, wordUint(b, 32)),
	}
}

func decodeInitializer(b []byte) decodedInitializer {
	if len(b) < 4+32*5 {
		fail("initializer too short: %d bytes", len(b))
	}
	args := b[4:]
	return decodedInitializer{
		Selector:  hex0x(b[:4]),
		Authority: addressWord(args, 0),
		Zkgm:      addressWord(args, 32),
		Name:      string(dynamicBytes(args, wordUint(args, 64))),
		Symbol:    string(dynamicBytes(args, wordUint(args, 96))),
		Decimals:  fmt.Sprint(wordUint(args, 128)),
	}
}

func addressWord(b []byte, offset int) string {
	w := word(b, offset)
	return hex0x(w[12:])
}

func dynamicBytes(base []byte, offset uint64) []byte {
	return dynamicBytesField("dynamic bytes", base, offset)
}

func dynamicBytesField(label string, base []byte, offset uint64) []byte {
	if offset > uint64(len(base)) || offset%32 != 0 {
		fail("%s: invalid dynamic offset %d in %d-byte payload", label, offset, len(base))
	}
	start := int(offset)
	length := wordUint(base, start)
	dataStart := start + 32
	dataEnd := dataStart + int(length)
	if dataEnd > len(base) {
		fail("%s: dynamic bytes length %d at offset %d exceeds %d-byte payload", label, length, offset, len(base))
	}
	return base[dataStart:dataEnd]
}

func wordUint(b []byte, offset int) uint64 {
	w := word(b, offset)
	if new(big.Int).SetBytes(w[:24]).Sign() != 0 {
		fail("word at offset %d does not fit uint64", offset)
	}
	return new(big.Int).SetBytes(w[24:]).Uint64()
}

func wordBig(b []byte, offset int) *big.Int {
	return new(big.Int).SetBytes(word(b, offset))
}

func word(b []byte, offset int) []byte {
	if offset < 0 || offset+32 > len(b) {
		fail("word offset %d exceeds %d-byte payload", offset, len(b))
	}
	return b[offset : offset+32]
}

func mustReadFixture() fixture {
	path := filepath.Join(fixtureDir(), "fixture.json")
	b, err := os.ReadFile(path)
	if err != nil {
		fail("read %s: %v", path, err)
	}
	var fx fixture
	if err := json.Unmarshal(b, &fx); err != nil {
		fail("decode %s: %v", path, err)
	}
	return fx
}

func fixtureDir() string {
	_, self, _, ok := runtime.Caller(0)
	if !ok {
		fail("cannot resolve fixture directory from source path")
	}
	return filepath.Join(filepath.Dir(self), "..", "..", "scenarios", "zkgm-tokenorder-vectors")
}

func expect(v vector, key string, got string) {
	want, ok := v.Expected[key]
	if !ok {
		fail("%s missing expected field %s", v.Name, key)
	}
	requireEqual(v.Name+" "+key, normalizeValue(got), normalizeValue(want))
}

func requireEqual(label, got, want string) {
	if got != want {
		fail("%s: got %s, want %s", label, got, want)
	}
}

func normalizeValue(v string) string {
	if strings.HasPrefix(v, "0x") || strings.HasPrefix(v, "0X") {
		return normalizedHex(v)
	}
	return v
}

func normalizedHex(s string) string {
	return "0x" + strings.ToLower(strings.TrimPrefix(strings.TrimPrefix(s, "0x"), "0X"))
}

func mustHex(s string) []byte {
	s = strings.TrimPrefix(strings.TrimPrefix(s, "0x"), "0X")
	if len(s)%2 != 0 {
		s = "0" + s
	}
	b, err := hex.DecodeString(s)
	if err != nil {
		fail("decode hex: %v", err)
	}
	return b
}

func hex0x(b []byte) string {
	return "0x" + strings.ToLower(hex.EncodeToString(b))
}

func fail(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "FAIL: "+format+"\n", args...)
	os.Exit(1)
}
