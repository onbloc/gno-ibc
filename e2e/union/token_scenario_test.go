package unione2e

import (
	"context"
	"crypto/rand"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"
)

const (
	evmPacketSendTopic = "0x635b5d234fe7abddfb29b6c8498780a3175c9002c537f20a3d1bf9d0e625b5fe"
	evmPacketAckTopic  = "0x41d958a7d93b50b1f7541c6fc345d0c4657b1e83497baa562c866611ac1f69bb"
)

type tokenScenarioEnv struct {
	cfg             config
	gnoSender       string
	evmSender       string
	evmPrivateKey   string
	unionMinter     string
	unionCW20Admin  string
	unionCW20CodeID uint64
	unionVoyagerDir string
}

type tokenOrder struct {
	Sender, Receiver, BaseToken, QuoteToken, Metadata string
	Amount                                            int64
}

func TestTokenScenarioEventHelpers(t *testing.T) {
	ack := make([]byte, 32)
	ack[31] = 1
	if ackTag(ack) != 1 {
		t.Fatal("success ack tag was not decoded")
	}
	var tx indexedTx
	tx.Response.Events = append(tx.Response.Events, struct {
		Type    string `json:"type"`
		PkgPath string `json:"pkg_path"`
		Attrs   []struct {
			Key   string `json:"key"`
			Value string `json:"value"`
		} `json:"attrs"`
	}{Type: "WriteAck", Attrs: []struct {
		Key   string `json:"key"`
		Value string `json:"value"`
	}{{Key: "acknowledgement[0]", Value: "0x01"}, {Key: "acknowledgement[1]", Value: "02"}}})
	if got := txEncodedAttr(tx, "WriteAck", "acknowledgement"); got != "0x0102" {
		t.Fatalf("joined event attr = %q", got)
	}
}

func TestTokenBridgeScenarios(t *testing.T) {
	cfg := loadConfig()
	if !cfg.RunPacketTests {
		t.Skip("set RUN_PACKET_TESTS=1 after both direct topologies are open")
	}
	requirePacketSetup(t, cfg)
	requireUnionEVMTopology(t, cfg)
	checkEVMReady(t, cfg)
	checkBeaconReady(t, cfg)

	gnoSender := os.Getenv("GNO_SENDER_ADDR")
	evmPrivateKey := os.Getenv("EVM_PRIVATE_KEY")
	if gnoSender == "" || evmPrivateKey == "" {
		t.Fatal("GNO_SENDER_ADDR and EVM_PRIVATE_KEY are required")
	}
	evmSender := mustCommand(t, "cast", "wallet", "address", "--private-key", evmPrivateKey)
	minter := queryUnionMinter(t, cfg)
	admin, codeID := queryUnionMinterConfig(t, cfg, minter)
	unionRepo := getenv("UNION_VOYAGER_DIR", filepath.Join("..", "..", "..", "union-voyager"))
	env := tokenScenarioEnv{
		cfg: cfg, gnoSender: gnoSender, evmSender: evmSender, evmPrivateKey: evmPrivateKey,
		unionMinter: minter, unionCW20Admin: admin, unionCW20CodeID: codeID,
		unionVoyagerDir: unionRepo,
	}

	t.Run("gno_native_to_evm", env.testGnoNativeToEVM)
	t.Run("evm_erc20_to_gno", env.testEVMERC20ToGno)
}

func (e tokenScenarioEnv) testGnoNativeToEVM(t *testing.T) {
	const amount int64 = 1
	tag := fmt.Sprintf("%09d", time.Now().UnixNano()%1_000_000_000)
	unionMetadata := e.unionMetadata(t, "Gno Native "+tag, "GNO"+tag[len(tag)-3:], 6)
	unionVoucher := predictUnionWrappedToken(t, e.cfg, e.unionMinter, e.cfg.UnionPacketChannelID, []byte("ugnot"), unionMetadata)

	gnoBefore := queryGnoBalance(t, e.cfg, e.gnoSender, "ugnot")
	gnoOrder := encodeTokenOrder(t, tokenOrder{
		Sender: asciiHex(e.gnoSender), Receiver: asciiHex(e.cfg.UnionPacketSender), BaseToken: asciiHex("ugnot"),
		QuoteToken: asciiHex(unionVoucher), Metadata: unionMetadata, Amount: amount,
	})
	relayGnoToUnion(t, e.cfg, gnoOrder, fmt.Sprintf("%dugnot", amount))
	requireUnionCW20(t, e.cfg, unionVoucher, "Gno Native "+tag, "GNO"+tag[len(tag)-3:], 6)
	if got := queryUnionCW20Balance(t, e.cfg, unionVoucher, e.cfg.UnionPacketSender); got != amount {
		t.Fatalf("Union CW20 mint delta = %d, want %d", got, amount)
	}
	if after := queryGnoBalance(t, e.cfg, e.gnoSender, "ugnot"); after > gnoBefore-amount {
		t.Fatalf("Gno ugnot balance did not decrease: before=%d after=%d", gnoBefore, after)
	}

	increaseUnionCW20Allowance(t, e.cfg, unionVoucher, e.unionMinter, amount)
	evmMetadata := evmMetadata(t, e.cfg, "Gno Native "+tag, "GNO"+tag[len(tag)-3:], 6)
	evmWrapped := predictEVMWrappedToken(t, e.cfg, e.cfg.EVMUnionChannelID, []byte(unionVoucher), evmMetadata)
	unionSenderBefore := queryUnionCW20Balance(t, e.cfg, unionVoucher, e.cfg.UnionPacketSender)
	unionEscrowBefore := queryUnionCW20Balance(t, e.cfg, unionVoucher, e.unionMinter)
	evmRecipientBefore := queryERC20Balance(t, e.cfg, evmWrapped, e.cfg.EVMRecipient)
	unionOrder := encodeTokenOrder(t, tokenOrder{
		Sender: asciiHex(e.cfg.UnionPacketSender), Receiver: e.cfg.EVMRecipient, BaseToken: asciiHex(unionVoucher),
		QuoteToken: evmWrapped, Metadata: evmMetadata, Amount: amount,
	})
	relayUnionToEVM(t, e.cfg, encodeInstruction(t, unionOrder), evmWrapped)
	if got := queryERC20String(t, e.cfg, evmWrapped, "0x06fdde03"); got != "Gno Native "+tag {
		t.Fatalf("EVM wrapped-token name = %q", got)
	}
	if got := queryERC20String(t, e.cfg, evmWrapped, "0x95d89b41"); got != "GNO"+tag[len(tag)-3:] {
		t.Fatalf("EVM wrapped-token symbol = %q", got)
	}
	if got := queryERC20Uint(t, e.cfg, evmWrapped, "0x313ce567"); got != 6 {
		t.Fatalf("EVM wrapped-token decimals = %d, want 6", got)
	}
	if got := queryERC20Uint(t, e.cfg, evmWrapped, "0x18160ddd"); got != uint64(amount) {
		t.Fatalf("EVM wrapped-token total supply = %d, want %d", got, amount)
	}
	if got := unionSenderBefore - queryUnionCW20Balance(t, e.cfg, unionVoucher, e.cfg.UnionPacketSender); got != amount {
		t.Fatalf("Union CW20 sender delta = %d, want %d", got, amount)
	}
	if got := queryUnionCW20Balance(t, e.cfg, unionVoucher, e.unionMinter) - unionEscrowBefore; got != amount {
		t.Fatalf("Union CW20 escrow delta = %d, want %d", got, amount)
	}
	if got := queryERC20Balance(t, e.cfg, evmWrapped, e.cfg.EVMRecipient) - evmRecipientBefore; got != amount {
		t.Fatalf("EVM wrapped-token delta = %d, want %d", got, amount)
	}
}

func (e tokenScenarioEnv) testEVMERC20ToGno(t *testing.T) {
	const amount int64 = 1_000_000_000_000
	tag := fmt.Sprintf("%09d", time.Now().UnixNano()%1_000_000_000)
	token := deployTestERC20(t, e, "EVM Test "+tag, "EVM"+tag[len(tag)-3:], 18)
	castSend(t, e.cfg, e.evmPrivateKey, token, "mint(address,uint256)", e.evmSender, strconv.FormatInt(amount, 10))
	castSend(t, e.cfg, e.evmPrivateKey, token, "approve(address,uint256)", e.cfg.EVMZKGM, strconv.FormatInt(amount, 10))

	unionMetadata := e.unionMetadata(t, "EVM Test "+tag, "EVM"+tag[len(tag)-3:], 18)
	unionVoucher := predictUnionWrappedToken(t, e.cfg, e.unionMinter, e.cfg.UnionEVMChannelID, mustDecodeHex(t, token), unionMetadata)
	evmBefore := queryERC20Balance(t, e.cfg, token, e.evmSender)
	evmEscrowBefore := queryERC20Balance(t, e.cfg, token, e.cfg.EVMZKGM)
	evmOrder := encodeTokenOrder(t, tokenOrder{
		Sender: e.evmSender, Receiver: asciiHex(e.cfg.UnionPacketSender), BaseToken: token,
		QuoteToken: asciiHex(unionVoucher), Metadata: unionMetadata, Amount: amount,
	})
	relayEVMToUnion(t, e, evmOrder)
	requireUnionCW20(t, e.cfg, unionVoucher, "EVM Test "+tag, "EVM"+tag[len(tag)-3:], 18)
	if got := evmBefore - queryERC20Balance(t, e.cfg, token, e.evmSender); got != amount {
		t.Fatalf("EVM ERC20 sender delta = %d, want %d", got, amount)
	}
	if got := queryERC20Balance(t, e.cfg, token, e.cfg.EVMZKGM) - evmEscrowBefore; got != amount {
		t.Fatalf("EVM ERC20 escrow delta = %d, want %d", got, amount)
	}
	if got := queryUnionCW20Balance(t, e.cfg, unionVoucher, e.cfg.UnionPacketSender); got != amount {
		t.Fatalf("Union CW20 mint delta = %d, want %d", got, amount)
	}

	increaseUnionCW20Allowance(t, e.cfg, unionVoucher, e.unionMinter, amount)
	gnoMetadata := gnoMetadata(t, "EVM Test "+tag, "EVM"+tag[len(tag)-3:], 18)
	gnoVoucher := predictGnoWrappedToken(t, e.cfg.GnoPacketChannelID, []byte(unionVoucher), gnoMetadata)
	gnoBefore := queryGnoVoucherBalance(t, e.cfg, gnoVoucher, e.gnoSender)
	unionSenderBefore := queryUnionCW20Balance(t, e.cfg, unionVoucher, e.cfg.UnionPacketSender)
	unionEscrowBefore := queryUnionCW20Balance(t, e.cfg, unionVoucher, e.unionMinter)
	unionOrder := encodeTokenOrder(t, tokenOrder{
		Sender: asciiHex(e.cfg.UnionPacketSender), Receiver: asciiHex(e.gnoSender), BaseToken: asciiHex(unionVoucher),
		QuoteToken: asciiHex(gnoVoucher), Metadata: gnoMetadata, Amount: amount,
	})
	relayUnionToGno(t, e.cfg, encodeInstruction(t, unionOrder))
	if got := unionSenderBefore - queryUnionCW20Balance(t, e.cfg, unionVoucher, e.cfg.UnionPacketSender); got != amount {
		t.Fatalf("Union CW20 sender delta = %d, want %d", got, amount)
	}
	if got := queryUnionCW20Balance(t, e.cfg, unionVoucher, e.unionMinter) - unionEscrowBefore; got != amount {
		t.Fatalf("Union CW20 escrow delta = %d, want %d", got, amount)
	}
	if got := queryGnoVoucherBalance(t, e.cfg, gnoVoucher, e.gnoSender) - gnoBefore; got != 1 {
		t.Fatalf("Gno downscaled voucher delta = %d, want 1", got)
	}
}

func relayGnoToUnion(t *testing.T, cfg config, operand, coins string) {
	t.Helper()
	baseline := captureVoyagerBaseline(t, cfg)
	after := latestGnoEventHeight(cfg.GnoIndexer, "PacketSend", map[string]string{"source_channel_id": cfg.GnoPacketChannelID})
	transferOnGno(t, cfg, gnoTransferRequest{ChannelID: cfg.GnoPacketChannelID, OperandHex: operand, SendCoins: coins, SaltHex: randomHex32(t)})
	send := waitForNewGnoEvent(t, cfg, "PacketSend", map[string]string{"source_channel_id": cfg.GnoPacketChannelID}, after, baseline)
	hash := txAttr(send, "PacketSend", "packet_hash")
	requireOneGnoEvent(t, cfg, "PacketSend", hash)
	enqueueGnoBlock(t, cfg, send.BlockHeight)
	recv := waitForUnionReceive(t, cfg, hash, send.BlockHeight, &baseline)
	write := waitForUnionEvent(t, cfg, "wasm-write_ack", hash)
	requireOneUnionEvent(t, cfg, "wasm-packet_recv", hash)
	requireOneUnionEvent(t, cfg, "wasm-write_ack", hash)
	if recv.Hash != write.Hash {
		t.Fatalf("Union PacketRecv tx %s differs from WriteAck tx %s", recv.Hash, write.Hash)
	}
	requireUnionAckSuccess(t, cfg, write.Hash)
	enqueueUnionBlock(t, cfg, write.Height)
	waitForNewGnoEvent(t, cfg, "PacketAck", map[string]string{"packet_hash": hash}, send.BlockHeight, baseline)
	requireOneGnoEvent(t, cfg, "PacketAck", hash)
	requireGnoPacketAcknowledged(t, cfg, hash)
	requirePacketVoyagerSuccess(t, cfg, baseline, hash)
}

func relayUnionToEVM(t *testing.T, cfg config, instruction, wrappedToken string) {
	t.Helper()
	baseline := captureVoyagerBaseline(t, cfg)
	evmFrom, err := queryEVMBlockNumber(cfg.EVMRPC)
	if err != nil {
		t.Fatal(err)
	}
	body := broadcastUnionPacket(t, cfg, unionTransferRequest{ChannelID: cfg.UnionEVMChannelID, Instruction: instruction, Salt: "0x" + randomHex32(t)})
	hash, height, _ := unionEvent(t, []byte(body), "wasm-packet_send")
	requireOneUnionEvent(t, cfg, "wasm-packet_send", hash)
	enqueueUnionBlock(t, cfg, height)
	recv := waitForEVMLog(t, cfg, baseline.Failed, cfg.EVMIBCHandler, packetRecvTopic, evmFrom+1, topicUint32(mustUint32(t, cfg.EVMUnionChannelID)), hash)
	write := waitForEVMLog(t, cfg, baseline.Failed, cfg.EVMIBCHandler, writeAckTopic, evmFrom+1, topicUint32(mustUint32(t, cfg.EVMUnionChannelID)), hash)
	requireEVMReceiveAndAck(t, cfg, evmFrom+1, hash, recv, write)
	if logs, err := queryEVMLogs(cfg.EVMRPC, cfg.EVMZKGM, evmFrom+1, createWrappedTokenTopic, topicUint32(mustUint32(t, cfg.EVMUnionChannelID)), topicAddress(wrappedToken)); err != nil || len(logs) != 1 {
		t.Fatalf("EVM CreateWrappedToken count = %d, want 1: %v", len(logs), err)
	}
	if code, err := queryEVMCode(cfg.EVMRPC, wrappedToken); err != nil || len(code) == 0 {
		t.Fatalf("EVM wrapped token was not created: %v", err)
	}
	block := mustHexUint64(t, write.BlockNumber)
	enqueueEVMBlock(t, cfg, block)
	waitForUnionEvent(t, cfg, "wasm-packet_ack", hash)
	requireOneUnionEvent(t, cfg, "wasm-packet_ack", hash)
	requireUnionPacketCommitmentRemoved(t, cfg, hash)
	requirePacketVoyagerSuccess(t, cfg, baseline, hash)
}

func relayEVMToUnion(t *testing.T, e tokenScenarioEnv, operand string) {
	t.Helper()
	baseline := captureVoyagerBaseline(t, e.cfg)
	from, err := queryEVMBlockNumber(e.cfg.EVMRPC)
	if err != nil {
		t.Fatal(err)
	}
	receipt := castSend(t, e.cfg, e.evmPrivateKey, e.cfg.EVMZKGM,
		"send(uint32,uint64,uint64,bytes32,(uint8,uint8,bytes))", e.cfg.EVMUnionChannelID, "0",
		strconv.FormatInt(time.Now().Add(time.Hour).UnixNano(), 10), "0x"+randomHex32(t), "(2,3,"+operand+")")
	var sendLogs []EVMLog
	for _, log := range receipt.Logs {
		if len(log.Topics) > 2 && strings.EqualFold(log.Address, e.cfg.EVMIBCHandler) && strings.EqualFold(log.Topics[0], evmPacketSendTopic) {
			sendLogs = append(sendLogs, log)
		}
	}
	if len(sendLogs) != 1 {
		t.Fatalf("EVM PacketSend count = %d, want 1", len(sendLogs))
	}
	hash := sendLogs[0].Topics[2]
	block := mustHexUint64(t, receipt.BlockNumber)
	enqueueEVMBlock(t, e.cfg, block)
	recv := waitForUnionEvent(t, e.cfg, "wasm-packet_recv", hash)
	write := waitForUnionEvent(t, e.cfg, "wasm-write_ack", hash)
	requireOneUnionEvent(t, e.cfg, "wasm-packet_recv", hash)
	requireOneUnionEvent(t, e.cfg, "wasm-write_ack", hash)
	if recv.Hash != write.Hash {
		t.Fatalf("Union PacketRecv tx %s differs from WriteAck tx %s", recv.Hash, write.Hash)
	}
	requireUnionAckSuccess(t, e.cfg, write.Hash)
	enqueueUnionBlock(t, e.cfg, write.Height)
	ack := waitForEVMLog(t, e.cfg, baseline.Failed, e.cfg.EVMIBCHandler, evmPacketAckTopic, from+1, topicUint32(mustUint32(t, e.cfg.EVMUnionChannelID)), hash)
	ackBytes, err := abiBytes(mustDecodeHex(t, ack.Data), 0)
	if err != nil || ackTag(ackBytes) != 1 {
		t.Fatalf("EVM PacketAck is not success: %v", err)
	}
	if logs, err := queryEVMLogs(e.cfg.EVMRPC, e.cfg.EVMIBCHandler, from+1, evmPacketAckTopic, topicUint32(mustUint32(t, e.cfg.EVMUnionChannelID)), hash); err != nil || len(logs) != 1 {
		t.Fatalf("EVM PacketAck count = %d, want 1: %v", len(logs), err)
	}
	requireEVMPacketInactive(t, e.cfg, hash)
	requirePacketVoyagerSuccess(t, e.cfg, baseline, hash)
}

func relayUnionToGno(t *testing.T, cfg config, instruction string) {
	t.Helper()
	baseline := captureVoyagerBaseline(t, cfg)
	body := broadcastUnionPacket(t, cfg, unionTransferRequest{ChannelID: cfg.UnionPacketChannelID, Instruction: instruction, Salt: "0x" + randomHex32(t)})
	hash, height, _ := unionEvent(t, []byte(body), "wasm-packet_send")
	requireOneUnionEvent(t, cfg, "wasm-packet_send", hash)
	enqueueUnionBlock(t, cfg, height)
	recv := waitForGnoEvent(t, cfg.GnoIndexer, "PacketRecv", map[string]string{"packet_hash": hash})
	write := waitForGnoEvent(t, cfg.GnoIndexer, "WriteAck", map[string]string{"packet_hash": hash})
	requireOneGnoEvent(t, cfg, "PacketRecv", hash)
	requireOneGnoEvent(t, cfg, "WriteAck", hash)
	if recv.Hash != write.Hash {
		t.Fatalf("Gno PacketRecv tx %s differs from WriteAck tx %s", recv.Hash, write.Hash)
	}
	if ackTag(mustDecodeHex(t, txEncodedAttr(write, "WriteAck", "acknowledgement"))) != 1 {
		t.Fatal("Gno WriteAck is not success")
	}
	enqueueGnoBlock(t, cfg, write.BlockHeight)
	waitForUnionEvent(t, cfg, "wasm-packet_ack", hash)
	requireOneUnionEvent(t, cfg, "wasm-packet_ack", hash)
	requireUnionPacketCommitmentRemoved(t, cfg, hash)
	requirePacketVoyagerSuccess(t, cfg, baseline, hash)
}

func (e tokenScenarioEnv) unionMetadata(t *testing.T, name, symbol string, decimals uint8) string {
	t.Helper()
	implementation, _ := json.Marshal(struct {
		Admin  string `json:"admin"`
		CodeID uint64 `json:"code_id"`
	}{e.unionCW20Admin, e.unionCW20CodeID})
	initializer, _ := json.Marshal(map[string]any{"init": map[string]any{
		"name": name, "symbol": symbol, "decimals": decimals, "initial_balances": []any{},
		"mint": map[string]any{"minter": e.unionMinter, "cap": nil}, "marketing": nil,
	}})
	return encodeMetadata(t, hexBytes(implementation), hexBytes(initializer))
}

func evmMetadata(t *testing.T, cfg config, name, symbol string, decimals uint8) string {
	t.Helper()
	initializer := mustCommand(t, "cast", "calldata", "initialize(address,address,string,string,uint8)", cfg.EVMManager, cfg.EVMZKGM, name, symbol, strconv.Itoa(int(decimals)))
	return encodeMetadata(t, cfg.EVMERC20Impl, initializer)
}

func gnoMetadata(t *testing.T, name, symbol string, decimals uint8) string {
	t.Helper()
	initializer := mustCommand(t, "cast", "abi-encode", "f(string,string,uint8)", name, symbol, strconv.Itoa(int(decimals)))
	return encodeMetadata(t, asciiHex("grc20"), initializer)
}

func encodeMetadata(t *testing.T, implementation, initializer string) string {
	t.Helper()
	return mustCommand(t, "cast", "abi-encode", "f(bytes,bytes)", implementation, initializer)
}

func encodeTokenOrder(t *testing.T, order tokenOrder) string {
	t.Helper()
	return mustCommand(t, "cast", "abi-encode", "f(bytes,bytes,bytes,uint256,bytes,uint256,uint8,bytes)",
		order.Sender, order.Receiver, order.BaseToken, strconv.FormatInt(order.Amount, 10), order.QuoteToken,
		strconv.FormatInt(order.Amount, 10), "0", order.Metadata)
}

func encodeInstruction(t *testing.T, operand string) string {
	t.Helper()
	return mustCommand(t, "cast", "abi-encode", "f(uint8,uint8,bytes)", "2", "3", operand)
}

func predictUnionWrappedToken(t *testing.T, cfg config, minter, channel string, base []byte, metadata string) string {
	t.Helper()
	image := mustCommand(t, "cast", "keccak", metadata)
	var response struct {
		WrappedToken string `json:"wrapped_token"`
	}
	queryUnionContract(t, cfg, minter, map[string]any{"predict_wrapped_token_v2": map[string]any{
		"path": "0", "channel_id": mustUint32(t, channel), "token": base64.StdEncoding.EncodeToString(base), "metadata_image": image,
	}}, &response)
	if response.WrappedToken == "" {
		t.Fatal("Union wrapped-token prediction is empty")
	}
	return response.WrappedToken
}

func predictEVMWrappedToken(t *testing.T, cfg config, channel string, base []byte, metadata string) string {
	t.Helper()
	decoded := castDecode(t, "f()(bytes,bytes)", metadata)
	out := mustCommand(t, "cast", "call", cfg.EVMZKGM,
		"predictWrappedTokenV2(uint256,uint32,bytes,(bytes,bytes))(address,bytes32)", "0", channel, hexBytes(base),
		fmt.Sprintf("(%s,%s)", decoded[0], decoded[1]), "--rpc-url", cfg.EVMRPC)
	return strings.Fields(out)[0]
}

func predictGnoWrappedToken(t *testing.T, channel string, base []byte, metadata string) string {
	t.Helper()
	image := mustCommand(t, "cast", "keccak", metadata)
	encoded := mustCommand(t, "cast", "abi-encode", "f(uint256,uint32,bytes,uint256)", "0", channel, hexBytes(base), image)
	hash := strings.TrimPrefix(mustCommand(t, "cast", "keccak", encoded), "0x")
	return "ibc/" + hash[:40]
}

func queryUnionMinter(t *testing.T, cfg config) string {
	t.Helper()
	var minter string
	queryUnionContract(t, cfg, cfg.UnionZKGMContract, map[string]any{"get_minter": map[string]any{}}, &minter)
	return minter
}

func queryUnionMinterConfig(t *testing.T, cfg config, minter string) (string, uint64) {
	t.Helper()
	var conf struct {
		CW20ImplCodeID uint64 `json:"cw20_impl_code_id"`
	}
	queryUnionRaw(t, cfg, minter, "conf", &conf)
	var admin string
	queryUnionRaw(t, cfg, minter, "admin", &admin)
	if admin == "" || conf.CW20ImplCodeID == 0 {
		t.Fatalf("invalid live Union minter config: admin=%q code_id=%d", admin, conf.CW20ImplCodeID)
	}
	return admin, conf.CW20ImplCodeID
}

func queryUnionRaw(t *testing.T, cfg config, contract, key string, result any) {
	t.Helper()
	out, err := dockerExec(cfg.UnionContainer, "uniond", "query", "wasm", "contract-state", "raw", contract, hex.EncodeToString([]byte(key)), "-o", "json")
	if err != nil {
		t.Fatalf("query Union raw %s/%s: %v\n%s", contract, key, err, out)
	}
	var response struct {
		Data string `json:"data"`
	}
	if err := json.Unmarshal([]byte(out), &response); err != nil {
		t.Fatal(err)
	}
	data, err := base64.StdEncoding.DecodeString(response.Data)
	if err != nil {
		t.Fatalf("decode Union raw %s/%s: %v data=%q", contract, key, err, data)
	}
	if err := json.Unmarshal(data, result); err != nil {
		t.Fatalf("decode Union raw %s/%s JSON: %v data=%q", contract, key, err, data)
	}
}

func queryUnionContract(t *testing.T, cfg config, contract string, query, result any) {
	t.Helper()
	if err := queryUnionCore(cfg.UnionContainer, contract, query, result); err != nil {
		t.Fatalf("query Union contract %s: %v", contract, err)
	}
}

func queryUnionCW20Balance(t *testing.T, cfg config, token, owner string) int64 {
	t.Helper()
	var response struct {
		Balance string `json:"balance"`
	}
	queryUnionContract(t, cfg, token, map[string]any{"balance": map[string]any{"address": owner}}, &response)
	n, err := strconv.ParseInt(response.Balance, 10, 64)
	if err != nil {
		t.Fatalf("parse CW20 balance %q: %v", response.Balance, err)
	}
	return n
}

func requireUnionCW20(t *testing.T, cfg config, token, name, symbol string, decimals uint8) {
	t.Helper()
	var info struct {
		Name, Symbol string
		Decimals     uint8
	}
	queryUnionContract(t, cfg, token, map[string]any{"token_info": map[string]any{}}, &info)
	if info.Name != name || info.Symbol != symbol || info.Decimals != decimals {
		t.Fatalf("Union CW20 metadata = %+v, want %q/%q/%d", info, name, symbol, decimals)
	}
}

func increaseUnionCW20Allowance(t *testing.T, cfg config, token, spender string, amount int64) {
	t.Helper()
	msg, _ := json.Marshal(map[string]any{"increase_allowance": map[string]any{"spender": spender, "amount": strconv.FormatInt(amount, 10)}})
	broadcastUnionContract(t, cfg, token, string(msg), "")
}

func queryGnoVoucherBalance(t *testing.T, cfg config, denom, owner string) int64 {
	t.Helper()
	expr := fmt.Sprintf("gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm.VoucherBalanceOf(%q,address(%q))", denom, owner)
	out := strings.TrimSpace(queryGnoQEval(t, cfg, expr))
	_, out, _ = strings.Cut(out, "data: ")
	var balance int64
	if _, err := fmt.Sscanf(strings.TrimSpace(out), "(%d int64)", &balance); err != nil {
		t.Fatalf("parse Gno voucher balance %q: %v", out, err)
	}
	return balance
}

func deployTestERC20(t *testing.T, e tokenScenarioEnv, name, symbol string, decimals uint8) string {
	t.Helper()
	out := mustCommand(t, "forge", "create", "--root", e.unionVoyagerDir, "--rpc-url", e.cfg.EVMRPC,
		"--private-key", e.evmPrivateKey, "--broadcast", "--json",
		"evm/tests/src/05-app/Zkgm.t.sol:TestERC20", "--constructor-args", name, symbol, strconv.Itoa(int(decimals)))
	var response struct {
		DeployedTo string `json:"deployedTo"`
	}
	if err := decodeCommandJSON(out, &response); err != nil || response.DeployedTo == "" {
		t.Fatalf("parse forge create output: %v\n%s", err, out)
	}
	return response.DeployedTo
}

func castSend(t *testing.T, cfg config, privateKey, contract, signature string, args ...string) EVMReceipt {
	t.Helper()
	cmdArgs := []string{"send", contract, signature}
	cmdArgs = append(cmdArgs, args...)
	cmdArgs = append(cmdArgs, "--rpc-url", cfg.EVMRPC, "--private-key", privateKey, "--json")
	out := mustCommand(t, "cast", cmdArgs...)
	var receipt EVMReceipt
	if err := decodeCommandJSON(out, &receipt); err != nil || receipt.Status != "0x1" {
		t.Fatalf("cast send failed: %v status=%s\n%s", err, receipt.Status, out)
	}
	return receipt
}

func requireUnionAckSuccess(t *testing.T, cfg config, txHash string) {
	t.Helper()
	body := queryUnionTxBody(t, cfg, txHash)
	ack := requireUnionTxEvent(t, body, "wasm-write_ack", "acknowledgement", "")
	if ackTag(mustDecodeHex(t, ack)) != 1 {
		t.Fatalf("Union WriteAck is not success: %s", ack)
	}
}

func queryUnionTxBody(t *testing.T, cfg config, hash string) []byte {
	t.Helper()
	out, err := dockerExec(cfg.UnionContainer, "uniond", "query", "tx", hash, "--node", "tcp://localhost:26657", "-o", "json")
	if err != nil {
		t.Fatalf("query Union tx %s: %v\n%s", hash, err, out)
	}
	return []byte(out)
}

func requireUnionTxEvent(t *testing.T, body []byte, eventType, key, want string) string {
	t.Helper()
	var tx struct {
		Events []struct {
			Type       string `json:"type"`
			Attributes []struct {
				Key, Value string
			} `json:"attributes"`
		} `json:"events"`
	}
	if err := json.Unmarshal(body, &tx); err != nil {
		t.Fatal(err)
	}
	var values []string
	for _, event := range tx.Events {
		if event.Type != eventType {
			continue
		}
		for _, attr := range event.Attributes {
			if attr.Key == key {
				values = append(values, attr.Value)
			}
		}
	}
	if len(values) != 1 || want != "" && values[0] != want {
		t.Fatalf("Union tx %s %s = %v, want one %q", eventType, key, values, want)
	}
	return values[0]
}

func requireEVMReceiveAndAck(t *testing.T, cfg config, from uint64, hash string, recv, write EVMLog) {
	t.Helper()
	if recv.TransactionHash != write.TransactionHash {
		t.Fatalf("EVM PacketRecv tx %s differs from WriteAck tx %s", recv.TransactionHash, write.TransactionHash)
	}
	receipt, err := queryEVMReceipt(cfg.EVMRPC, recv.TransactionHash)
	if err != nil || receipt.Status != "0x1" {
		t.Fatalf("EVM receive receipt status=%q: %v", receipt.Status, err)
	}
	ack, err := abiBytes(mustDecodeHex(t, write.Data), 0)
	if err != nil || ackTag(ack) != 1 {
		t.Fatalf("EVM WriteAck is not success: %v", err)
	}
	for label, topic := range map[string]string{"PacketRecv": packetRecvTopic, "WriteAck": writeAckTopic} {
		logs, err := queryEVMLogs(cfg.EVMRPC, cfg.EVMIBCHandler, from, topic, topicUint32(mustUint32(t, cfg.EVMUnionChannelID)), hash)
		if err != nil || len(logs) != 1 {
			t.Fatalf("EVM %s count = %d, want 1: %v", label, len(logs), err)
		}
	}
}

func requireOneGnoEvent(t *testing.T, cfg config, eventType, hash string) {
	t.Helper()
	events, err := queryGnoEvents(cfg.GnoIndexer, eventType, map[string]string{"packet_hash": hash})
	if err != nil || len(events) != 1 {
		t.Fatalf("Gno %s count = %d, want 1: %v", eventType, len(events), err)
	}
}

func requireGnoPacketAcknowledged(t *testing.T, cfg config, hash string) {
	t.Helper()
	batchHash := strings.TrimPrefix(hash, "0x")
	if b, err := hex.DecodeString(batchHash); err != nil || len(b) != 32 {
		t.Fatalf("invalid packet hash %q", hash)
	}
	expr := fmt.Sprintf("gno.land/r/onbloc/ibc/union/testing/e2e_setup.QueryBatchPacketCommitment(%q)", batchHash)
	want := "0x02" + strings.Repeat("00", 31)
	if out := queryGnoQEval(t, cfg, expr); !strings.Contains(out, want) {
		t.Fatalf("Gno packet commitment is not acknowledged: got %s want %s", out, want)
	}
}

func requireEVMPacketInactive(t *testing.T, cfg config, hash string) {
	t.Helper()
	path := mustCommand(t, "cast", "abi-encode", "f(uint256,bytes32)", "4", hash)
	key := mustCommand(t, "cast", "keccak", path)
	commitment := mustCommand(t, "cast", "call", cfg.EVMIBCHandler, "commitments(bytes32)(bytes32)", key, "--rpc-url", cfg.EVMRPC)
	want := "0x02" + strings.Repeat("0", 62)
	if !strings.EqualFold(commitment, want) {
		t.Fatalf("EVM packet commitment is still active: %s", commitment)
	}
}

func requirePacketVoyagerSuccess(t *testing.T, cfg config, baseline voyagerBaseline, hash string) {
	t.Helper()
	requireNoNewVoyagerFailed(t, cfg, baseline)
	if done := voyagerRowsAfter(t, cfg, "done", baseline.Done); !strings.Contains(strings.ToLower(done), strings.ToLower(hash)) {
		t.Fatalf("Voyager done rows do not contain packet %s:\n%s", hash, done)
	}
}

func txEncodedAttr(tx indexedTx, eventType, key string) string {
	if value := txAttr(tx, eventType, key); value != "" {
		return value
	}
	var parts []string
	for i := 0; ; i++ {
		part := txAttr(tx, eventType, fmt.Sprintf("%s[%d]", key, i))
		if part == "" {
			break
		}
		parts = append(parts, part)
	}
	return strings.Join(parts, "")
}

func ackTag(ack []byte) uint64 {
	if len(ack) < 32 {
		return 0
	}
	return uint64(ack[31])
}

func mustHexUint64(t *testing.T, value string) uint64 {
	t.Helper()
	n, err := strconv.ParseUint(strings.TrimPrefix(value, "0x"), 16, 64)
	if err != nil {
		t.Fatal(err)
	}
	return n
}

func mustCommand(t *testing.T, name string, args ...string) string {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()
	out, err := exec.CommandContext(ctx, name, args...).CombinedOutput()
	if err != nil {
		t.Fatalf("%s failed: %v\n%s", name, err, out)
	}
	return strings.TrimSpace(string(out))
}

func decodeCommandJSON(out string, result any) error {
	start, end := strings.Index(out, "{"), strings.LastIndex(out, "}")
	if start < 0 || end < start {
		return fmt.Errorf("JSON object not found")
	}
	return json.Unmarshal([]byte(out[start:end+1]), result)
}

func randomHex32(t *testing.T) string {
	t.Helper()
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		t.Fatal(err)
	}
	return hex.EncodeToString(b)
}

func asciiHex(value string) string { return hexBytes([]byte(value)) }

func hexBytes(value []byte) string { return "0x" + hex.EncodeToString(value) }
