package unione2e

import (
	"context"
	"crypto/rand"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os/exec"
	"strconv"
	"strings"
	"testing"
	"time"
)

const (
	evmPacketSendTopic = "0x635b5d234fe7abddfb29b6c8498780a3175c9002c537f20a3d1bf9d0e625b5fe"
	evmPacketAckTopic  = "0x41d958a7d93b50b1f7541c6fc345d0c4657b1e83497baa562c866611ac1f69bb"
)

type bridgeHarness struct {
	cfg             config
	evmSender       string
	unionMinter     string
	unionCW20Admin  string
	unionCW20CodeID uint64
}

type tokenMetadata struct {
	name     string
	symbol   string
	decimals uint8
}

type bridgeOutcome struct {
	packetHash string
	token      string
	sender     int64
	escrow     int64
	recipient  int64
}

type tokenOrder struct {
	Sender, Receiver, BaseToken, QuoteToken, Metadata string
	Amount                                            int64
}

func newBridgeHarness(t *testing.T) *bridgeHarness {
	t.Helper()
	cfg := loadConfig()
	if !cfg.RunPackets {
		t.Skip("set RUN_PACKET_TESTS=1 after both direct topologies are open")
	}
	if err := cfg.validatePacket(); err != nil {
		t.Fatal(err)
	}

	requirePacketSetup(t, cfg)
	requireUnionEVMTopology(t, cfg)
	checkEVMReady(t, cfg.EVM)
	checkBeaconReady(t, cfg.EVM)

	h := &bridgeHarness{
		cfg:       cfg,
		evmSender: mustCommand(t, "cast", "wallet", "address", "--private-key", cfg.EVM.PrivateKey),
	}
	queryUnionContract(t, cfg.Union, cfg.Union.ZKGM, map[string]any{"get_minter": map[string]any{}}, &h.unionMinter)
	h.unionCW20Admin, h.unionCW20CodeID = queryUnionMinterConfig(t, cfg.Union, h.unionMinter)
	return h
}

func (h *bridgeHarness) gnoNativeToUnion(t *testing.T, baseToken string, amount int64, recipient string, metadata tokenMetadata) bridgeOutcome {
	t.Helper()
	encodedMetadata := h.unionMetadata(t, metadata)
	wrappedToken := predictUnionWrappedToken(t, h.cfg.Union, h.unionMinter, h.cfg.Topology.UnionGno.ChannelID, []byte(baseToken), encodedMetadata)
	senderBefore := queryGnoBalance(t, h.cfg.Gno, h.cfg.Gno.Sender, baseToken)
	order := encodeTokenOrder(t, tokenOrder{
		Sender: asciiHex(h.cfg.Gno.Sender), Receiver: asciiHex(recipient), BaseToken: asciiHex(baseToken),
		QuoteToken: asciiHex(wrappedToken), Metadata: encodedMetadata, Amount: amount,
	})

	baseline := captureVoyagerBaseline(t, h.cfg.Voyager)
	after := latestGnoEventHeight(h.cfg.Gno.Indexer, "PacketSend", map[string]string{"source_channel_id": h.cfg.Topology.Gno.ChannelID})
	broadcastGnoPacket(t, h.cfg.Gno, h.cfg.Topology.Gno.ChannelID, order, fmt.Sprintf("%d%s", amount, baseToken), randomHex32(t))
	send := waitForNewGnoEvent(t, h.cfg, "PacketSend", map[string]string{"source_channel_id": h.cfg.Topology.Gno.ChannelID}, after, baseline)
	hash := txAttr(send, "PacketSend", "packet_hash")
	requireOneGnoEvent(t, h.cfg.Gno, "PacketSend", hash)
	enqueueGnoBlock(t, h.cfg.Voyager, h.cfg.Gno.ChainID, send.BlockHeight)
	recv := waitForUnionReceive(t, h.cfg, hash, send.BlockHeight, &baseline)
	write := h.requireUnionReceiveAndAck(t, hash, recv)
	enqueueUnionBlock(t, h.cfg.Voyager, h.cfg.Union.ChainID, write.Height)
	waitForNewGnoEvent(t, h.cfg, "PacketAck", map[string]string{"packet_hash": hash}, send.BlockHeight, baseline)
	requireOneGnoEvent(t, h.cfg.Gno, "PacketAck", hash)
	requireGnoPacketAcknowledged(t, h.cfg.Gno, hash)
	requirePacketVoyagerSuccess(t, h.cfg.Voyager, baseline, hash)
	requireUnionCW20(t, h.cfg.Union, wrappedToken, metadata)
	out := bridgeOutcome{
		packetHash: hash, token: wrappedToken,
		sender:    senderBefore - queryGnoBalance(t, h.cfg.Gno, h.cfg.Gno.Sender, baseToken),
		recipient: queryUnionCW20Balance(t, h.cfg.Union, wrappedToken, recipient),
	}
	t.Logf("success packet=%s token=%s deltas sender=%d escrow=%d recipient=%d", out.packetHash, out.token, out.sender, out.escrow, out.recipient)
	return out
}

func (h *bridgeHarness) unionCW20ToEVM(t *testing.T, baseToken string, amount int64, recipient string, metadata tokenMetadata) bridgeOutcome {
	t.Helper()
	increaseUnionCW20Allowance(t, h.cfg.Union, baseToken, h.unionMinter, amount)
	encodedMetadata := evmMetadata(t, h.cfg.EVM, metadata)
	wrappedToken := predictEVMWrappedToken(t, h.cfg.EVM, h.cfg.Topology.EVM.ChannelID, []byte(baseToken), encodedMetadata)
	senderBefore := queryUnionCW20Balance(t, h.cfg.Union, baseToken, h.cfg.Union.PacketSender)
	escrowBefore := queryUnionCW20Balance(t, h.cfg.Union, baseToken, h.unionMinter)
	recipientBefore := queryERC20Balance(t, h.cfg.EVM, wrappedToken, recipient)
	order := encodeTokenOrder(t, tokenOrder{
		Sender: asciiHex(h.cfg.Union.PacketSender), Receiver: recipient, BaseToken: asciiHex(baseToken),
		QuoteToken: wrappedToken, Metadata: encodedMetadata, Amount: amount,
	})

	baseline := captureVoyagerBaseline(t, h.cfg.Voyager)
	evmFrom, err := queryEVMBlockNumber(h.cfg.EVM.RPC)
	evmFrom = must(t, evmFrom, err)
	body := broadcastUnionPacket(t, h.cfg.Union, h.cfg.Topology.UnionEVM.ChannelID, encodeInstruction(t, order), "0x"+randomHex32(t))
	hash, height := unionEvent(t, []byte(body), "wasm-packet_send")
	requireOneUnionEvent(t, h.cfg.Union, "wasm-packet_send", hash)
	enqueueUnionBlock(t, h.cfg.Voyager, h.cfg.Union.ChainID, height)
	recv := waitForEVMLog(t, h.cfg, baseline.Failed, h.cfg.EVM.IBCHandler, packetRecvTopic, evmFrom+1, topicUint32(mustUint32(t, h.cfg.Topology.EVM.ChannelID)), hash)
	write := waitForEVMLog(t, h.cfg, baseline.Failed, h.cfg.EVM.IBCHandler, writeAckTopic, evmFrom+1, topicUint32(mustUint32(t, h.cfg.Topology.EVM.ChannelID)), hash)
	requireEVMReceiveAndAck(t, h.cfg, evmFrom+1, h.cfg.Topology.EVM.ChannelID, hash, recv, write)
	if logs, err := queryEVMLogs(h.cfg.EVM.RPC, h.cfg.EVM.ZKGM, evmFrom+1, createWrappedTokenTopic, topicUint32(mustUint32(t, h.cfg.Topology.EVM.ChannelID)), topicAddress(wrappedToken)); err != nil || len(logs) != 1 {
		t.Fatalf("EVM CreateWrappedToken count = %d, want 1: %v", len(logs), err)
	}
	if code, err := queryEVMCode(h.cfg.EVM.RPC, wrappedToken); err != nil || len(code) == 0 {
		t.Fatalf("EVM wrapped token was not created: %v", err)
	}
	block := mustHexUint64(t, write.BlockNumber)
	enqueueEVMBlock(t, h.cfg.Voyager, h.cfg.EVM.ChainID, block)
	waitForUnionEvent(t, h.cfg, "wasm-packet_ack", hash)
	requireOneUnionEvent(t, h.cfg.Union, "wasm-packet_ack", hash)
	requireUnionPacketCommitmentRemoved(t, h.cfg.Union, hash)
	requirePacketVoyagerSuccess(t, h.cfg.Voyager, baseline, hash)
	if got := queryERC20String(t, h.cfg.EVM, wrappedToken, "0x06fdde03"); got != metadata.name {
		t.Fatalf("EVM wrapped-token name = %q, want %q", got, metadata.name)
	}
	if got := queryERC20String(t, h.cfg.EVM, wrappedToken, "0x95d89b41"); got != metadata.symbol {
		t.Fatalf("EVM wrapped-token symbol = %q, want %q", got, metadata.symbol)
	}
	if got := queryERC20Uint(t, h.cfg.EVM, wrappedToken, "0x313ce567"); got != uint64(metadata.decimals) {
		t.Fatalf("EVM wrapped-token decimals = %d, want %d", got, metadata.decimals)
	}
	if got := queryERC20Uint(t, h.cfg.EVM, wrappedToken, "0x18160ddd"); got != uint64(amount) {
		t.Fatalf("EVM wrapped-token total supply = %d, want %d", got, amount)
	}
	out := bridgeOutcome{
		packetHash: hash, token: wrappedToken,
		sender:    senderBefore - queryUnionCW20Balance(t, h.cfg.Union, baseToken, h.cfg.Union.PacketSender),
		escrow:    queryUnionCW20Balance(t, h.cfg.Union, baseToken, h.unionMinter) - escrowBefore,
		recipient: queryERC20Balance(t, h.cfg.EVM, wrappedToken, recipient) - recipientBefore,
	}
	t.Logf("success packet=%s token=%s deltas sender=%d escrow=%d recipient=%d", out.packetHash, out.token, out.sender, out.escrow, out.recipient)
	return out
}

func (h *bridgeHarness) evmERC20ToUnion(t *testing.T, amount int64, recipient string, metadata tokenMetadata) bridgeOutcome {
	t.Helper()
	baseToken := h.deployTestERC20(t, metadata)
	castSend(t, h.cfg.EVM, baseToken, "mint(address,uint256)", h.evmSender, strconv.FormatInt(amount, 10))
	castSend(t, h.cfg.EVM, baseToken, "approve(address,uint256)", h.cfg.EVM.ZKGM, strconv.FormatInt(amount, 10))
	encodedMetadata := h.unionMetadata(t, metadata)
	wrappedToken := predictUnionWrappedToken(t, h.cfg.Union, h.unionMinter, h.cfg.Topology.UnionEVM.ChannelID, mustDecodeHex(t, baseToken), encodedMetadata)
	senderBefore := queryERC20Balance(t, h.cfg.EVM, baseToken, h.evmSender)
	escrowBefore := queryERC20Balance(t, h.cfg.EVM, baseToken, h.cfg.EVM.ZKGM)
	operand := encodeTokenOrder(t, tokenOrder{
		Sender: h.evmSender, Receiver: asciiHex(recipient), BaseToken: baseToken,
		QuoteToken: asciiHex(wrappedToken), Metadata: encodedMetadata, Amount: amount,
	})

	baseline := captureVoyagerBaseline(t, h.cfg.Voyager)
	from, err := queryEVMBlockNumber(h.cfg.EVM.RPC)
	from = must(t, from, err)
	receipt := castSend(t, h.cfg.EVM, h.cfg.EVM.ZKGM,
		"send(uint32,uint64,uint64,bytes32,(uint8,uint8,bytes))", h.cfg.Topology.EVM.ChannelID, "0",
		strconv.FormatInt(time.Now().Add(time.Hour).UnixNano(), 10), "0x"+randomHex32(t), "(2,3,"+operand+")")
	var sendLogs []EVMLog
	for _, log := range receipt.Logs {
		if len(log.Topics) > 2 && strings.EqualFold(log.Address, h.cfg.EVM.IBCHandler) && strings.EqualFold(log.Topics[0], evmPacketSendTopic) {
			sendLogs = append(sendLogs, log)
		}
	}
	if len(sendLogs) != 1 {
		t.Fatalf("EVM PacketSend count = %d, want 1", len(sendLogs))
	}
	hash := sendLogs[0].Topics[2]
	block := mustHexUint64(t, receipt.BlockNumber)
	enqueueEVMBlock(t, h.cfg.Voyager, h.cfg.EVM.ChainID, block)
	recv := waitForUnionEvent(t, h.cfg, "wasm-packet_recv", hash)
	write := h.requireUnionReceiveAndAck(t, hash, recv)
	enqueueUnionBlock(t, h.cfg.Voyager, h.cfg.Union.ChainID, write.Height)
	ack := waitForEVMLog(t, h.cfg, baseline.Failed, h.cfg.EVM.IBCHandler, evmPacketAckTopic, from+1, topicUint32(mustUint32(t, h.cfg.Topology.EVM.ChannelID)), hash)
	ackBytes, err := abiBytes(mustDecodeHex(t, ack.Data), 0)
	if err != nil || ackTag(ackBytes) != 1 {
		t.Fatalf("EVM PacketAck is not success: %v", err)
	}
	if logs, err := queryEVMLogs(h.cfg.EVM.RPC, h.cfg.EVM.IBCHandler, from+1, evmPacketAckTopic, topicUint32(mustUint32(t, h.cfg.Topology.EVM.ChannelID)), hash); err != nil || len(logs) != 1 {
		t.Fatalf("EVM PacketAck count = %d, want 1: %v", len(logs), err)
	}
	requireEVMPacketInactive(t, h.cfg.EVM, hash)
	requirePacketVoyagerSuccess(t, h.cfg.Voyager, baseline, hash)
	requireUnionCW20(t, h.cfg.Union, wrappedToken, metadata)
	out := bridgeOutcome{
		packetHash: hash, token: wrappedToken,
		sender:    senderBefore - queryERC20Balance(t, h.cfg.EVM, baseToken, h.evmSender),
		escrow:    queryERC20Balance(t, h.cfg.EVM, baseToken, h.cfg.EVM.ZKGM) - escrowBefore,
		recipient: queryUnionCW20Balance(t, h.cfg.Union, wrappedToken, recipient),
	}
	t.Logf("success packet=%s token=%s deltas sender=%d escrow=%d recipient=%d", out.packetHash, out.token, out.sender, out.escrow, out.recipient)
	return out
}

func (h *bridgeHarness) unionCW20ToGno(t *testing.T, baseToken string, amount int64, recipient string, metadata tokenMetadata) bridgeOutcome {
	t.Helper()
	increaseUnionCW20Allowance(t, h.cfg.Union, baseToken, h.unionMinter, amount)
	encodedMetadata := gnoMetadata(t, metadata)
	wrappedToken := predictGnoWrappedToken(t, h.cfg.Topology.Gno.ChannelID, []byte(baseToken), encodedMetadata)
	senderBefore := queryUnionCW20Balance(t, h.cfg.Union, baseToken, h.cfg.Union.PacketSender)
	escrowBefore := queryUnionCW20Balance(t, h.cfg.Union, baseToken, h.unionMinter)
	recipientBefore := queryGnoVoucherBalance(t, h.cfg.Gno, wrappedToken, recipient)
	order := encodeTokenOrder(t, tokenOrder{
		Sender: asciiHex(h.cfg.Union.PacketSender), Receiver: asciiHex(recipient), BaseToken: asciiHex(baseToken),
		QuoteToken: asciiHex(wrappedToken), Metadata: encodedMetadata, Amount: amount,
	})

	baseline := captureVoyagerBaseline(t, h.cfg.Voyager)
	body := broadcastUnionPacket(t, h.cfg.Union, h.cfg.Topology.UnionGno.ChannelID, encodeInstruction(t, order), "0x"+randomHex32(t))
	hash, height := unionEvent(t, []byte(body), "wasm-packet_send")
	requireOneUnionEvent(t, h.cfg.Union, "wasm-packet_send", hash)
	enqueueUnionBlock(t, h.cfg.Voyager, h.cfg.Union.ChainID, height)
	recv := waitForGnoEvent(t, h.cfg.Gno.Indexer, "PacketRecv", map[string]string{"packet_hash": hash})
	write := waitForGnoEvent(t, h.cfg.Gno.Indexer, "WriteAck", map[string]string{"packet_hash": hash})
	requireOneGnoEvent(t, h.cfg.Gno, "PacketRecv", hash)
	requireOneGnoEvent(t, h.cfg.Gno, "WriteAck", hash)
	if recv.Hash != write.Hash {
		t.Fatalf("Gno PacketRecv tx %s differs from WriteAck tx %s", recv.Hash, write.Hash)
	}
	if ackTag(mustDecodeHex(t, txEncodedAttr(write, "WriteAck", "acknowledgement"))) != 1 {
		t.Fatal("Gno WriteAck is not success")
	}
	enqueueGnoBlock(t, h.cfg.Voyager, h.cfg.Gno.ChainID, write.BlockHeight)
	waitForUnionEvent(t, h.cfg, "wasm-packet_ack", hash)
	requireOneUnionEvent(t, h.cfg.Union, "wasm-packet_ack", hash)
	requireUnionPacketCommitmentRemoved(t, h.cfg.Union, hash)
	requirePacketVoyagerSuccess(t, h.cfg.Voyager, baseline, hash)
	out := bridgeOutcome{
		packetHash: hash, token: wrappedToken,
		sender:    senderBefore - queryUnionCW20Balance(t, h.cfg.Union, baseToken, h.cfg.Union.PacketSender),
		escrow:    queryUnionCW20Balance(t, h.cfg.Union, baseToken, h.unionMinter) - escrowBefore,
		recipient: queryGnoVoucherBalance(t, h.cfg.Gno, wrappedToken, recipient) - recipientBefore,
	}
	t.Logf("success packet=%s token=%s deltas sender=%d escrow=%d recipient=%d", out.packetHash, out.token, out.sender, out.escrow, out.recipient)
	return out
}

func (h *bridgeHarness) requireUnionReceiveAndAck(t *testing.T, hash string, recv UnionTx) UnionTx {
	t.Helper()
	write := waitForUnionEvent(t, h.cfg, "wasm-write_ack", hash)
	requireOneUnionEvent(t, h.cfg.Union, "wasm-packet_recv", hash)
	requireOneUnionEvent(t, h.cfg.Union, "wasm-write_ack", hash)
	if recv.Hash != write.Hash {
		t.Fatalf("Union PacketRecv tx %s differs from WriteAck tx %s", recv.Hash, write.Hash)
	}
	requireUnionAckSuccess(t, h.cfg.Union, write.Hash)
	return write
}

func (h *bridgeHarness) unionMetadata(t *testing.T, metadata tokenMetadata) string {
	t.Helper()
	implementation, _ := json.Marshal(struct {
		Admin  string `json:"admin"`
		CodeID uint64 `json:"code_id"`
	}{h.unionCW20Admin, h.unionCW20CodeID})
	initializer, _ := json.Marshal(map[string]any{"init": map[string]any{
		"name": metadata.name, "symbol": metadata.symbol, "decimals": metadata.decimals, "initial_balances": []any{},
		"mint": map[string]any{"minter": h.unionMinter, "cap": nil}, "marketing": nil,
	}})
	return encodeMetadata(t, hexBytes(implementation), hexBytes(initializer))
}

func evmMetadata(t *testing.T, cfg evmConfig, metadata tokenMetadata) string {
	t.Helper()
	initializer := mustCommand(t, "cast", "calldata", "initialize(address,address,string,string,uint8)", cfg.Manager, cfg.ZKGM, metadata.name, metadata.symbol, strconv.Itoa(int(metadata.decimals)))
	return encodeMetadata(t, cfg.ERC20Impl, initializer)
}

func gnoMetadata(t *testing.T, metadata tokenMetadata) string {
	t.Helper()
	initializer := mustCommand(t, "cast", "abi-encode", "f(string,string,uint8)", metadata.name, metadata.symbol, strconv.Itoa(int(metadata.decimals)))
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

func predictUnionWrappedToken(t *testing.T, cfg unionConfig, minter, channel string, base []byte, metadata string) string {
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

func predictEVMWrappedToken(t *testing.T, cfg evmConfig, channel string, base []byte, metadata string) string {
	t.Helper()
	decoded := castDecode(t, "f()(bytes,bytes)", metadata)
	out := mustCommand(t, "cast", "call", cfg.ZKGM,
		"predictWrappedTokenV2(uint256,uint32,bytes,(bytes,bytes))(address,bytes32)", "0", channel, hexBytes(base),
		fmt.Sprintf("(%s,%s)", decoded[0], decoded[1]), "--rpc-url", cfg.RPC)
	return strings.Fields(out)[0]
}

func predictGnoWrappedToken(t *testing.T, channel string, base []byte, metadata string) string {
	t.Helper()
	image := mustCommand(t, "cast", "keccak", metadata)
	encoded := mustCommand(t, "cast", "abi-encode", "f(uint256,uint32,bytes,uint256)", "0", channel, hexBytes(base), image)
	hash := strings.TrimPrefix(mustCommand(t, "cast", "keccak", encoded), "0x")
	return "ibc/" + hash[:40]
}

func queryUnionMinterConfig(t *testing.T, cfg unionConfig, minter string) (string, uint64) {
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

func queryUnionRaw(t *testing.T, cfg unionConfig, contract, key string, result any) {
	t.Helper()
	out, err := dockerExec(cfg.Container, "uniond", "query", "wasm", "contract-state", "raw", contract, hex.EncodeToString([]byte(key)), "-o", "json")
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

func queryUnionContract(t *testing.T, cfg unionConfig, contract string, query, result any) {
	t.Helper()
	if err := queryUnionCore(cfg.Container, contract, query, result); err != nil {
		t.Fatalf("query Union contract %s: %v", contract, err)
	}
}

func queryUnionCW20Balance(t *testing.T, cfg unionConfig, token, owner string) int64 {
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

func requireUnionCW20(t *testing.T, cfg unionConfig, token string, metadata tokenMetadata) {
	t.Helper()
	var info struct {
		Name, Symbol string
		Decimals     uint8
	}
	queryUnionContract(t, cfg, token, map[string]any{"token_info": map[string]any{}}, &info)
	if info.Name != metadata.name || info.Symbol != metadata.symbol || info.Decimals != metadata.decimals {
		t.Fatalf("Union CW20 metadata = %+v, want %q/%q/%d", info, metadata.name, metadata.symbol, metadata.decimals)
	}
}

func increaseUnionCW20Allowance(t *testing.T, cfg unionConfig, token, spender string, amount int64) {
	t.Helper()
	msg, _ := json.Marshal(map[string]any{"increase_allowance": map[string]any{"spender": spender, "amount": strconv.FormatInt(amount, 10)}})
	broadcastUnionContract(t, cfg, token, string(msg))
}

func queryGnoVoucherBalance(t *testing.T, cfg gnoConfig, denom, owner string) int64 {
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

func (h *bridgeHarness) deployTestERC20(t *testing.T, metadata tokenMetadata) string {
	t.Helper()
	out := mustCommand(t, "forge", "create", "--root", ".", "--out", t.TempDir(), "--no-cache", "--rpc-url", h.cfg.EVM.RPC,
		"--private-key", h.cfg.EVM.PrivateKey, "--broadcast", "--json",
		"fixtures/TestERC20.sol:TestERC20", "--constructor-args", metadata.name, metadata.symbol, strconv.Itoa(int(metadata.decimals)))
	var response struct {
		DeployedTo string `json:"deployedTo"`
	}
	if err := decodeCommandJSON(out, &response); err != nil || response.DeployedTo == "" {
		t.Fatalf("parse forge create output: %v\n%s", err, out)
	}
	return response.DeployedTo
}

func castSend(t *testing.T, cfg evmConfig, contract, signature string, args ...string) EVMReceipt {
	t.Helper()
	cmdArgs := []string{"send", contract, signature}
	cmdArgs = append(cmdArgs, args...)
	cmdArgs = append(cmdArgs, "--rpc-url", cfg.RPC, "--private-key", cfg.PrivateKey, "--json")
	out := mustCommand(t, "cast", cmdArgs...)
	var receipt EVMReceipt
	if err := decodeCommandJSON(out, &receipt); err != nil || receipt.Status != "0x1" {
		t.Fatalf("cast send failed: %v status=%s\n%s", err, receipt.Status, out)
	}
	return receipt
}

func requireUnionAckSuccess(t *testing.T, cfg unionConfig, txHash string) {
	t.Helper()
	out, err := dockerExec(cfg.Container, "uniond", "query", "tx", txHash, "--node", "tcp://localhost:26657", "-o", "json")
	if err != nil {
		t.Fatalf("query Union tx %s: %v\n%s", txHash, err, out)
	}
	var tx struct {
		Events []struct {
			Type       string `json:"type"`
			Attributes []struct {
				Key, Value string
			} `json:"attributes"`
		} `json:"events"`
	}
	if err := json.Unmarshal([]byte(out), &tx); err != nil {
		t.Fatal(err)
	}
	var values []string
	for _, event := range tx.Events {
		if event.Type != "wasm-write_ack" {
			continue
		}
		for _, attr := range event.Attributes {
			if attr.Key == "acknowledgement" {
				values = append(values, attr.Value)
			}
		}
	}
	if len(values) != 1 {
		t.Fatalf("Union tx wasm-write_ack acknowledgement = %v, want exactly one", values)
	}
	if ackTag(mustDecodeHex(t, values[0])) != 1 {
		t.Fatalf("Union WriteAck is not success: %s", values[0])
	}
}

func requireEVMReceiveAndAck(t *testing.T, cfg config, from uint64, channel, hash string, recv, write EVMLog) {
	t.Helper()
	if recv.TransactionHash != write.TransactionHash {
		t.Fatalf("EVM PacketRecv tx %s differs from WriteAck tx %s", recv.TransactionHash, write.TransactionHash)
	}
	receipt, err := queryEVMReceipt(cfg.EVM.RPC, recv.TransactionHash)
	if err != nil || receipt.Status != "0x1" {
		t.Fatalf("EVM receive receipt status=%q: %v", receipt.Status, err)
	}
	ack, err := abiBytes(mustDecodeHex(t, write.Data), 0)
	if err != nil || ackTag(ack) != 1 {
		t.Fatalf("EVM WriteAck is not success: %v", err)
	}
	for label, topic := range map[string]string{"PacketRecv": packetRecvTopic, "WriteAck": writeAckTopic} {
		logs, err := queryEVMLogs(cfg.EVM.RPC, cfg.EVM.IBCHandler, from, topic, topicUint32(mustUint32(t, channel)), hash)
		if err != nil || len(logs) != 1 {
			t.Fatalf("EVM %s count = %d, want 1: %v", label, len(logs), err)
		}
	}
}

func requireOneGnoEvent(t *testing.T, cfg gnoConfig, eventType, hash string) {
	t.Helper()
	events, err := queryGnoEvents(cfg.Indexer, eventType, map[string]string{"packet_hash": hash})
	if err != nil || len(events) != 1 {
		t.Fatalf("Gno %s count = %d, want 1: %v", eventType, len(events), err)
	}
}

func requireGnoPacketAcknowledged(t *testing.T, cfg gnoConfig, hash string) {
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

func requireEVMPacketInactive(t *testing.T, cfg evmConfig, hash string) {
	t.Helper()
	path := mustCommand(t, "cast", "abi-encode", "f(uint256,bytes32)", "4", hash)
	key := mustCommand(t, "cast", "keccak", path)
	commitment := mustCommand(t, "cast", "call", cfg.IBCHandler, "commitments(bytes32)(bytes32)", key, "--rpc-url", cfg.RPC)
	want := "0x02" + strings.Repeat("0", 62)
	if !strings.EqualFold(commitment, want) {
		t.Fatalf("EVM packet commitment is still active: %s", commitment)
	}
}

func requirePacketVoyagerSuccess(t *testing.T, cfg voyagerConfig, baseline voyagerBaseline, hash string) {
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
	return must(t, n, err)
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
