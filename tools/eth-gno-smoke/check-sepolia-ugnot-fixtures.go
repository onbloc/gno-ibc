//go:build ignore

// Command check-sepolia-ugnot-fixtures validates committed Union Sepolia ugnot
// observations without making network calls. It is a standalone `go run` tool,
// kept out of package builds so it can share this directory with sibling tools.
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

const (
	ugnotToken          = "0x4271eb8f0243f1e1f303912841fdce55c06cf223"
	proxyImplementation = "0xaf739f34ddf951cbc24fdbba4f76213688e13627"
	transferTopic       = "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"
	// unionEventTopic is the burn-side raw Union event. See testdata/sepolia/README.md.
	unionEventTopic = "0x635b5d234fe7abddfb29b6c8498780a3175c9002c537f20a3d1bf9d0e625b5fe"

	zeroAddress = "0x0000000000000000000000000000000000000000"
	burnTxHash  = "0xfbd180c2706b966b669b5c001e4f71b3f413914718f5f2c31f11de69086973d1"
)

type transferFixture struct {
	Token struct {
		Address  string `json:"address"`
		Symbol   string `json:"symbol"`
		Decimals int    `json:"decimals"`
	} `json:"token"`
	TransferEventSignature string        `json:"transfer_event_signature"`
	Logs                   []transferLog `json:"logs"`
}

type transferLog struct {
	TxHash     string   `json:"transaction_hash"`
	Action     string   `json:"action"`
	Address    string   `json:"address"`
	Topics     []string `json:"topics"`
	Data       string   `json:"data"`
	From       string   `json:"from"`
	To         string   `json:"to"`
	AmountRaw  string   `json:"amount_raw"`
	AmountText string   `json:"amount_decimal"`
}

type rpcTxResponse struct {
	Result struct {
		Hash  string `json:"hash"`
		From  string `json:"from"`
		To    string `json:"to"`
		Input string `json:"input"`
	} `json:"result"`
}

type rpcReceiptResponse struct {
	Result struct {
		TransactionHash string       `json:"transactionHash"`
		Logs            []receiptLog `json:"logs"`
	} `json:"result"`
}

type receiptLog struct {
	Address string   `json:"address"`
	Topics  []string `json:"topics"`
	Data    string   `json:"data"`
}

func main() {
	transfers := mustReadJSON[transferFixture]("ugnot-token-transfers.json")
	requireEqual("token address", strings.ToLower(transfers.Token.Address), ugnotToken)
	requireEqual("token symbol", transfers.Token.Symbol, "ugnot")
	requireEqual("token decimals", fmt.Sprint(transfers.Token.Decimals), "6")
	requireEqual("transfer signature", strings.ToLower(transfers.TransferEventSignature), transferTopic)
	requireEqual("transfer log count", fmt.Sprint(len(transfers.Logs)), "3")

	netRaw := big.NewInt(0)
	for _, log := range transfers.Logs {
		requireEqual("transfer log token address", strings.ToLower(log.Address), ugnotToken)
		if len(log.Topics) < 3 {
			fail("transfer log %s has %d topics, want 3", log.TxHash, len(log.Topics))
		}
		requireEqual("transfer topic[0]", strings.ToLower(log.Topics[0]), transferTopic)
		requireEqual("transfer topic from", topicAddress(log.Topics[1]), strings.ToLower(log.From))
		requireEqual("transfer topic to", topicAddress(log.Topics[2]), strings.ToLower(log.To))
		requireEqual("transfer data amount", wordDecimal(log.Data), log.AmountRaw)
		requireEqual("transfer decimal amount", format6(log.AmountRaw), log.AmountText)

		amount := mustBig10(log.AmountRaw)
		switch log.Action {
		case "mint":
			requireEqual("mint from", strings.ToLower(log.From), zeroAddress)
			netRaw.Add(netRaw, amount)
		case "burn":
			requireEqual("burn to", strings.ToLower(log.To), zeroAddress)
			netRaw.Sub(netRaw, amount)
		default:
			fail("unexpected transfer action %q", log.Action)
		}
	}
	requireEqual("net minted raw amount", netRaw.String(), "1999999")

	tx := mustReadJSON[rpcTxResponse]("ugnot-burn-tx.json")
	requireEqual("burn tx hash", strings.ToLower(tx.Result.Hash), burnTxHash)
	decoded := decodeBurnInput(tx.Result.Input)
	requireEqual("burn selector", decoded.Selector, "0xff0d7c2f")
	requireEqual("instruction version", decoded.Version, "2")
	requireEqual("instruction opcode", decoded.Opcode, "3")
	requireEqual("base token", decoded.BaseToken, ugnotToken)
	requireEqual("base amount", decoded.BaseAmount, "1")
	requireEqual("quote token", decoded.QuoteToken, "0x75676e6f74") // "ugnot" as bytes
	requireEqual("quote amount", decoded.QuoteAmount, "1")
	requireEqual("token order kind", decoded.Kind, "2")
	requireEqual("metadata implementation", decoded.MetadataImplementation, proxyImplementation)
	requireEqual("initializer selector", decoded.InitializerSelector, "0x8420ce99")
	requireEqual("initializer token name", decoded.InitializerName, "gno.land")
	requireEqual("initializer token symbol", decoded.InitializerSymbol, "ugnot")
	requireEqual("initializer decimals", decoded.InitializerDecimals, "6")
	requireEqual("sender", decoded.Sender, "0x2c96e52fce14baa13868ca8182f8a7903e4e76e0")
	// receiver is the ASCII-encoded Gno address g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5.
	requireEqual("receiver", decoded.Receiver, "0x67316a67386d74757475396b6868667763346e786d756863706674663070616a6468667673716635")

	receipt := mustReadJSON[rpcReceiptResponse]("ugnot-burn-receipt.json")
	requireEqual("burn receipt tx hash", strings.ToLower(receipt.Result.TransactionHash), burnTxHash)
	var transferLogs, unionLogs int
	for _, log := range receipt.Result.Logs {
		if strings.EqualFold(log.Address, ugnotToken) && len(log.Topics) > 0 && strings.EqualFold(log.Topics[0], transferTopic) {
			transferLogs++
		}
		if len(log.Topics) > 0 && strings.EqualFold(log.Topics[0], unionEventTopic) {
			unionLogs++
		}
	}
	requireEqual("burn receipt transfer logs", fmt.Sprint(transferLogs), "1")
	requireEqual("burn receipt raw Union event logs", fmt.Sprint(unionLogs), "1")

	fmt.Println("PASS: Sepolia Union ugnot fixtures")
}

type decodedBurnInput struct {
	Selector               string
	Version                string
	Opcode                 string
	Sender                 string
	Receiver               string
	BaseToken              string
	BaseAmount             string
	QuoteToken             string
	QuoteAmount            string
	Kind                   string
	MetadataImplementation string
	InitializerSelector    string
	InitializerName        string
	InitializerSymbol      string
	InitializerDecimals    string
}

// decodeBurnInput decodes the burn tx calldata: a Union ucs03-zkgm Instruction
// whose operand is a TokenOrderV2 carrying a TokenMetadata (implementation plus
// an ERC-20 initializer). Offsets follow the ABI head layout of each struct.
func decodeBurnInput(inputHex string) decodedBurnInput {
	b := mustHex(inputHex)
	if len(b) < 4+32*5 {
		fail("burn input too short: %d bytes", len(b))
	}
	args := b[4:]
	instructionOffset := wordUint(args, 4*32)
	if instructionOffset > uint64(len(args)) {
		fail("instruction offset %d exceeds %d-byte args", instructionOffset, len(args))
	}
	instruction := args[instructionOffset:]
	version := wordUint(instruction, 0)
	opcode := wordUint(instruction, 32)
	operandOffset := wordUint(instruction, 64)
	operand := dynamicBytes(instruction, operandOffset)

	sender := dynamicBytes(operand, wordUint(operand, 0))
	receiver := dynamicBytes(operand, wordUint(operand, 32))
	baseToken := dynamicBytes(operand, wordUint(operand, 64))
	baseAmount := wordBig(operand, 96)
	quoteToken := dynamicBytes(operand, wordUint(operand, 128))
	quoteAmount := wordBig(operand, 160)
	kind := wordUint(operand, 192)
	metadata := dynamicBytes(operand, wordUint(operand, 224))

	implementation := dynamicBytes(metadata, wordUint(metadata, 0))
	initializer := dynamicBytes(metadata, wordUint(metadata, 32))
	if len(initializer) < 4+32*5 {
		fail("initializer too short: %d bytes", len(initializer))
	}
	initializerArgs := initializer[4:]
	name := string(dynamicBytes(initializerArgs, wordUint(initializerArgs, 64)))
	symbol := string(dynamicBytes(initializerArgs, wordUint(initializerArgs, 96)))
	decimals := wordUint(initializerArgs, 128)

	return decodedBurnInput{
		Selector:               "0x" + hex.EncodeToString(b[:4]),
		Version:                fmt.Sprint(version),
		Opcode:                 fmt.Sprint(opcode),
		Sender:                 hex0x(sender),
		Receiver:               hex0x(receiver),
		BaseToken:              hex0x(baseToken),
		BaseAmount:             baseAmount.String(),
		QuoteToken:             hex0x(quoteToken),
		QuoteAmount:            quoteAmount.String(),
		Kind:                   fmt.Sprint(kind),
		MetadataImplementation: hex0x(implementation),
		InitializerSelector:    hex0x(initializer[:4]),
		InitializerName:        name,
		InitializerSymbol:      symbol,
		InitializerDecimals:    fmt.Sprint(decimals),
	}
}

func dynamicBytes(base []byte, offset uint64) []byte {
	if offset > uint64(len(base)) || offset%32 != 0 {
		fail("invalid dynamic offset %d in %d-byte payload", offset, len(base))
	}
	start := int(offset)
	length := wordUint(base, start)
	dataStart := start + 32
	dataEnd := dataStart + int(length)
	if dataEnd > len(base) {
		fail("dynamic bytes length %d at offset %d exceeds %d-byte payload", length, offset, len(base))
	}
	return base[dataStart:dataEnd]
}

func wordUint(b []byte, offset int) uint64 {
	word := word(b, offset)
	if new(big.Int).SetBytes(word[:24]).Sign() != 0 {
		fail("word at offset %d does not fit uint64", offset)
	}
	return new(big.Int).SetBytes(word[24:]).Uint64()
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

// sepoliaFixtureDir resolves the fixture directory relative to this source file
// so the validator works regardless of the caller's working directory.
func sepoliaFixtureDir() string {
	_, self, _, ok := runtime.Caller(0)
	if !ok {
		fail("cannot resolve fixture directory from source path")
	}
	return filepath.Join(filepath.Dir(self), "testdata", "sepolia")
}

func mustReadJSON[T any](name string) T {
	var out T
	path := filepath.Join(sepoliaFixtureDir(), name)
	b, err := os.ReadFile(path)
	if err != nil {
		fail("read %s: %v", path, err)
	}
	if err := json.Unmarshal(b, &out); err != nil {
		fail("decode %s: %v", path, err)
	}
	return out
}

func topicAddress(topic string) string {
	topic = strings.ToLower(strings.TrimPrefix(topic, "0x"))
	if len(topic) != 64 {
		fail("invalid address topic length %d", len(topic))
	}
	return "0x" + topic[24:]
}

func wordDecimal(s string) string {
	return new(big.Int).SetBytes(mustHex(s)).String()
}

func format6(raw string) string {
	n := mustBig10(raw)
	q, r := new(big.Int), new(big.Int)
	q.QuoRem(n, big.NewInt(1000000), r)
	return fmt.Sprintf("%s.%06d", q.String(), r.Int64())
}

func mustBig10(s string) *big.Int {
	n, ok := new(big.Int).SetString(s, 10)
	if !ok {
		fail("invalid decimal integer %q", s)
	}
	return n
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
	return "0x" + hex.EncodeToString(b)
}

func requireEqual(label, got, want string) {
	if got != want {
		fail("%s: got %s, want %s", label, got, want)
	}
}

func fail(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "FAIL: "+format+"\n", args...)
	os.Exit(1)
}
