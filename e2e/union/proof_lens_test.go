package unione2e

import (
	"encoding/json"
	"fmt"
	"math/big"
	"strconv"
	"strings"
	"testing"
	"time"
)

func TestGnoEVMDirectTopology(t *testing.T) {
	cfg := loadConfig()
	if !cfg.RunPackets {
		t.Skip("set RUN_PACKET_TESTS=1 to check the live direct Gno-EVM topology")
	}
	if err := cfg.validatePacket(); err != nil {
		t.Fatal(err)
	}
	requireGnoEVMDirectTopology(t, cfg)
}

func requireGnoEVMDirectTopology(t *testing.T, cfg config) {
	t.Helper()
	if got := queryGnoQEval(t, cfg.Gno, fmt.Sprintf("gno.land/r/onbloc/ibc/union/core.QueryClientType(%s)", cfg.Topology.Gno.ClientID)); !strings.Contains(got, `("cometbls" string)`) {
		t.Fatalf("Gno Union client %s is not cometbls: %s", cfg.Topology.Gno.ClientID, got)
	}
	if got := queryGnoQEval(t, cfg.Gno, fmt.Sprintf("gno.land/r/onbloc/ibc/union/core.QueryClientType(%s)", cfg.Topology.GnoEVM.ClientID)); !strings.Contains(got, `("state-lens/ics23/mpt" string)`) {
		t.Fatalf("Gno direct client %s is not state-lens/ics23/mpt: %s", cfg.Topology.GnoEVM.ClientID, got)
	}
	for _, id := range []string{cfg.Topology.Gno.ClientID, cfg.Topology.GnoEVM.ClientID} {
		if got := queryGnoQEval(t, cfg.Gno, fmt.Sprintf("gno.land/r/onbloc/ibc/union/core.GetClientStatus(%s)", id)); !strings.Contains(got, `("1" string)`) {
			t.Fatalf("Gno client %s is not active: %s", id, got)
		}
	}
	for id, want := range map[string]string{
		cfg.Topology.UnionGno.ClientID: "gno",
		cfg.Topology.UnionEVM.ClientID: "trusted/evm/mpt",
	} {
		var clientType, status string
		clientID := mustUint32(t, id)
		if err := queryUnionCore(cfg.Union.Container, cfg.Union.Core, map[string]any{"get_client_type": map[string]any{"client_id": clientID}}, &clientType); err != nil || clientType != want {
			t.Fatalf("Union client %s type = %q, want %q: %v", id, clientType, want, err)
		}
		if err := queryUnionCore(cfg.Union.Container, cfg.Union.Core, map[string]any{"get_status": map[string]any{"client_id": clientID}}, &status); err != nil || status != "active" {
			t.Fatalf("Union client %s status = %q: %v", id, status, err)
		}
	}

	unionClient := mustUint32(t, cfg.Topology.EVM.ClientID)
	unionClientTypeData, err := evmCall(cfg.EVM.RPC, cfg.EVM.IBCHandler, evmUint32CallData("0x1296c148", unionClient))
	unionClientTypeData = must(t, unionClientTypeData, err)
	unionClientType, err := abiString(unionClientTypeData, 0)
	if unionClientType = must(t, unionClientType, err); unionClientType != "cometbls" {
		t.Fatalf("EVM Union client type = %q, want cometbls", unionClientType)
	}

	evmClient := mustUint32(t, cfg.Topology.EVMGno.ClientID)
	clientTypeData, err := evmCall(cfg.EVM.RPC, cfg.EVM.IBCHandler, evmUint32CallData("0x1296c148", evmClient))
	clientTypeData = must(t, clientTypeData, err)
	clientType, err := abiString(clientTypeData, 0)
	clientType = must(t, clientType, err)
	if clientType != "proof-lens" {
		t.Fatalf("EVM direct client type = %q, want proof-lens", clientType)
	}
	registered := strings.Fields(mustCommand(t, "cast", "call", cfg.EVM.IBCHandler, "clientRegistry(string)(address)", "proof-lens", "--rpc-url", cfg.EVM.RPC))[0]
	implData, err := evmCall(cfg.EVM.RPC, cfg.EVM.IBCHandler, evmUint32CallData("0x5f5d288e", evmClient))
	implData = must(t, implData, err)
	impl, err := abiAddress(implData, 0)
	impl = must(t, impl, err)
	if !strings.EqualFold(registered, impl) {
		t.Fatalf("EVM proof-lens client implementation = %s, registry = %s", impl, registered)
	}
	code, err := queryEVMCode(cfg.EVM.RPC, registered)
	if code = must(t, code, err); len(code) == 0 {
		t.Fatalf("EVM proof-lens implementation %s has no code", registered)
	}
	for _, id := range []string{cfg.Topology.EVM.ClientID, cfg.Topology.EVMGno.ClientID} {
		impl := strings.Fields(mustCommand(t, "cast", "call", cfg.EVM.IBCHandler, "getClient(uint32)(address)", id, "--rpc-url", cfg.EVM.RPC))[0]
		if frozen := strings.TrimSpace(mustCommand(t, "cast", "call", impl, "isFrozen(uint32)(bool)", id, "--rpc-url", cfg.EVM.RPC)); frozen != "false" {
			t.Fatalf("EVM client %s is not active: frozen=%s", id, frozen)
		}
	}

	type connection struct {
		State                    string `json:"state"`
		ClientID                 uint32 `json:"client_id"`
		CounterpartyClientID     uint32 `json:"counterparty_client_id"`
		CounterpartyConnectionID uint32 `json:"counterparty_connection_id"`
	}
	type channel struct {
		State                 string `json:"state"`
		ConnectionID          uint32 `json:"connection_id"`
		CounterpartyChannelID uint32 `json:"counterparty_channel_id"`
		CounterpartyPortID    string `json:"counterparty_port_id"`
		Version               string `json:"version"`
	}

	var gnoConnection, evmConnection connection
	queryVoyagerIBCState(t, cfg, cfg.Gno.ChainID, "connection", cfg.Topology.GnoEVM.ConnectionID, &gnoConnection)
	queryVoyagerIBCState(t, cfg, cfg.EVM.ChainID, "connection", cfg.Topology.EVMGno.ConnectionID, &evmConnection)
	if gnoConnection.State != "open" || gnoConnection.ClientID != mustUint32(t, cfg.Topology.GnoEVM.ClientID) || gnoConnection.CounterpartyClientID != evmClient || gnoConnection.CounterpartyConnectionID != mustUint32(t, cfg.Topology.EVMGno.ConnectionID) {
		t.Fatalf("Gno direct connection differs: %+v", gnoConnection)
	}
	if evmConnection.State != "open" || evmConnection.ClientID != evmClient || evmConnection.CounterpartyClientID != mustUint32(t, cfg.Topology.GnoEVM.ClientID) || evmConnection.CounterpartyConnectionID != mustUint32(t, cfg.Topology.GnoEVM.ConnectionID) {
		t.Fatalf("EVM direct connection differs: %+v", evmConnection)
	}

	var gnoChannel, evmChannel channel
	queryVoyagerIBCState(t, cfg, cfg.Gno.ChainID, "channel", cfg.Topology.GnoEVM.ChannelID, &gnoChannel)
	queryVoyagerIBCState(t, cfg, cfg.EVM.ChainID, "channel", cfg.Topology.EVMGno.ChannelID, &evmChannel)
	gnoPort := fmt.Sprintf("0x%x", []byte("gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"))
	if gnoChannel.State != "open" || gnoChannel.ConnectionID != mustUint32(t, cfg.Topology.GnoEVM.ConnectionID) || gnoChannel.CounterpartyChannelID != mustUint32(t, cfg.Topology.EVMGno.ChannelID) || !strings.EqualFold(gnoChannel.CounterpartyPortID, cfg.EVM.ZKGM) || gnoChannel.Version != "ucs03-zkgm-0" {
		t.Fatalf("Gno direct channel differs: %+v", gnoChannel)
	}
	if evmChannel.State != "open" || evmChannel.ConnectionID != mustUint32(t, cfg.Topology.EVMGno.ConnectionID) || evmChannel.CounterpartyChannelID != mustUint32(t, cfg.Topology.GnoEVM.ChannelID) || !strings.EqualFold(evmChannel.CounterpartyPortID, gnoPort) || evmChannel.Version != "ucs03-zkgm-0" {
		t.Fatalf("EVM direct channel differs: %+v", evmChannel)
	}
}

func queryVoyagerIBCState(t *testing.T, cfg config, chain, kind, id string, result any) {
	t.Helper()
	path := fmt.Sprintf(`{"%s":{"%s_id":%s}}`, kind, kind, id)
	out := voyagerCLI(t, cfg.Voyager, "rpc", "ibc-state", chain, path)
	var response struct {
		State json.RawMessage `json:"state"`
	}
	if err := json.Unmarshal([]byte(out), &response); err != nil || len(response.State) == 0 || string(response.State) == "null" {
		t.Fatalf("decode %s %s on %s: %v\n%s", kind, id, chain, err, out)
	}
	if err := json.Unmarshal(response.State, result); err != nil {
		t.Fatalf("decode %s %s state on %s: %v\n%s", kind, id, chain, err, out)
	}
}

func TestGnoNativeToEVMProofLens(t *testing.T) {
	h := newBridgeHarness(t)
	requireGnoEVMDirectTopology(t, h.cfg)

	const amount = "1"
	tag := fmt.Sprintf("%09d", time.Now().UnixNano()%1_000_000_000)
	metadata := tokenMetadata{name: "Gno Direct " + tag, symbol: "GND" + tag[len(tag)-3:], decimals: 6}
	encodedMetadata := evmMetadata(t, h.cfg.EVM, metadata)
	wrappedToken := predictEVMWrappedToken(t, h.cfg.EVM, h.cfg.Topology.EVMGno.ChannelID, []byte("ugnot"), encodedMetadata)
	recipientBefore := queryERC20Balance(t, h.cfg.EVM, wrappedToken, h.cfg.EVM.Recipient)
	order := encodeTokenOrder(t, tokenOrder{
		Sender: asciiHex(h.cfg.Gno.Sender), Receiver: h.cfg.EVM.Recipient, BaseToken: asciiHex("ugnot"),
		QuoteToken: wrappedToken, Metadata: encodedMetadata, Amount: amount, Kind: tokenOrderKindInitialize,
	})

	baseline := captureVoyagerBaseline(t, h.cfg.Voyager)
	evmFrom, err := queryEVMBlockNumber(h.cfg.EVM.RPC)
	evmFrom = must(t, evmFrom, err)
	after := latestGnoEventHeight(h.cfg.Gno.Indexer, "PacketSend", map[string]string{"source_channel_id": h.cfg.Topology.GnoEVM.ChannelID})
	broadcastGnoPacket(t, h.cfg.Gno, h.cfg.Topology.GnoEVM.ChannelID, order, "1ugnot", randomHex32(t), time.Now().Add(time.Hour).UnixNano())
	send := waitForNewGnoEvent(t, h.cfg, "PacketSend", map[string]string{"source_channel_id": h.cfg.Topology.GnoEVM.ChannelID}, after, baseline)
	hash := txAttr(send, "PacketSend", "packet_hash")
	requireOneGnoEvent(t, h.cfg.Gno, "PacketSend", hash)

	proofHeight := send.BlockHeight + 1 // Gno proofs expose the post-PacketSend state at the next height.
	path := packetCommitmentPath(t, hash)
	committedHeight := waitForUnionMembershipCommit(t, h.cfg, baseline.Failed, h.cfg.Topology.UnionGno.ClientID, proofHeight, path)
	t.Logf("Union committed the Gno membership proof at height %d", committedHeight)

	recv := waitForEVMLog(t, h.cfg, baseline.Failed, h.cfg.EVM.IBCHandler, packetRecvTopic, evmFrom+1, topicUint32(mustUint32(t, h.cfg.Topology.EVMGno.ChannelID)), hash)
	write := waitForEVMLog(t, h.cfg, baseline.Failed, h.cfg.EVM.IBCHandler, writeAckTopic, evmFrom+1, topicUint32(mustUint32(t, h.cfg.Topology.EVMGno.ChannelID)), hash)
	requireEVMReceiveAndAck(t, h.cfg, evmFrom+1, h.cfg.Topology.EVMGno.ChannelID, hash, recv, write)
	createLogs, err := queryEVMLogs(h.cfg.EVM.RPC, h.cfg.EVM.ZKGM, evmFrom+1, createWrappedTokenTopic, topicUint32(mustUint32(t, h.cfg.Topology.EVMGno.ChannelID)), topicAddress(wrappedToken))
	if err != nil || len(createLogs) != 1 {
		t.Fatalf("EVM CreateWrappedToken count = %d, want 1: %v", len(createLogs), err)
	}
	code, err := queryEVMCode(h.cfg.EVM.RPC, wrappedToken)
	if code = must(t, code, err); len(code) == 0 {
		t.Fatalf("EVM wrapped token %s was not created", wrappedToken)
	}
	if got := new(big.Int).Sub(queryERC20Balance(t, h.cfg.EVM, wrappedToken, h.cfg.EVM.Recipient), recipientBefore); got.Cmp(big.NewInt(1)) != 0 {
		t.Fatalf("EVM wrapped-token recipient delta = %s, want %s", got, amount)
	}

	waitForNewGnoEvent(t, h.cfg, "PacketAck", map[string]string{"packet_hash": hash}, send.BlockHeight, baseline)
	requireOneGnoEvent(t, h.cfg.Gno, "PacketAck", hash)
	requireGnoPacketAcknowledged(t, h.cfg.Gno, hash)
	requirePacketVoyagerSuccess(t, h.cfg.Voyager, baseline, hash)
	requireNoForbiddenRelayPath(t, h.cfg.Voyager, baseline)
}

func TestEVMERC20ToGnoStateLens(t *testing.T) {
	h := newBridgeHarness(t)
	requireGnoEVMDirectTopology(t, h.cfg)

	const amount = "1000000000000"
	amountInt, ok := new(big.Int).SetString(amount, 10)
	if !ok {
		t.Fatal("invalid test amount")
	}
	tag := fmt.Sprintf("%09d", time.Now().UnixNano()%1_000_000_000)
	metadata := tokenMetadata{name: "EVM Direct " + tag, symbol: "EVD" + tag[len(tag)-3:], decimals: 18}
	baseToken := h.deployTestERC20(t, metadata)
	castSend(t, h.cfg.EVM, baseToken, "mint(address,uint256)", h.evmSender, amount)
	castSend(t, h.cfg.EVM, baseToken, "approve(address,uint256)", h.cfg.EVM.ZKGM, amount)

	encodedMetadata := gnoMetadata(t, metadata)
	wrappedToken := predictGnoWrappedToken(t, h.cfg.Topology.GnoEVM.ChannelID, mustDecodeHex(t, baseToken), encodedMetadata)
	senderBefore := queryERC20Balance(t, h.cfg.EVM, baseToken, h.evmSender)
	escrowBefore := queryERC20Balance(t, h.cfg.EVM, baseToken, h.cfg.EVM.ZKGM)
	recipientBefore := queryGnoVoucherBalance(t, h.cfg.Gno, wrappedToken, h.cfg.Gno.Sender)
	operand := encodeTokenOrder(t, tokenOrder{
		Sender: h.evmSender, Receiver: asciiHex(h.cfg.Gno.Sender), BaseToken: baseToken,
		QuoteToken: asciiHex(wrappedToken), Metadata: encodedMetadata, Amount: amount, Kind: tokenOrderKindInitialize,
	})

	baseline := captureVoyagerBaseline(t, h.cfg.Voyager)
	from, err := queryEVMBlockNumber(h.cfg.EVM.RPC)
	from = must(t, from, err)
	receipt := broadcastEVMPacket(t, h.cfg.EVM, h.cfg.Topology.EVMGno.ChannelID, operand, time.Now().Add(time.Hour).UnixNano())
	hash := evmPacketHashFromReceipt(t, h.cfg.EVM, receipt)

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

	ack := waitForEVMLog(t, h.cfg, baseline.Failed, h.cfg.EVM.IBCHandler, evmPacketAckTopic, from+1, topicUint32(mustUint32(t, h.cfg.Topology.EVMGno.ChannelID)), hash)
	ackBytes, err := abiBytes(mustDecodeHex(t, ack.Data), 0)
	if err != nil || ackTag(ackBytes) != 1 {
		t.Fatalf("EVM PacketAck is not success: %v", err)
	}
	if logs, err := queryEVMLogs(h.cfg.EVM.RPC, h.cfg.EVM.IBCHandler, from+1, evmPacketAckTopic, topicUint32(mustUint32(t, h.cfg.Topology.EVMGno.ChannelID)), hash); err != nil || len(logs) != 1 {
		t.Fatalf("EVM PacketAck count = %d, want 1: %v", len(logs), err)
	}
	requireEVMPacketInactive(t, h.cfg.EVM, hash)
	requirePacketVoyagerSuccess(t, h.cfg.Voyager, baseline, hash)
	requireNoForbiddenRelayPath(t, h.cfg.Voyager, baseline)

	sender := new(big.Int).Sub(senderBefore, queryERC20Balance(t, h.cfg.EVM, baseToken, h.evmSender))
	escrow := new(big.Int).Sub(queryERC20Balance(t, h.cfg.EVM, baseToken, h.cfg.EVM.ZKGM), escrowBefore)
	recipient := queryGnoVoucherBalance(t, h.cfg.Gno, wrappedToken, h.cfg.Gno.Sender) - recipientBefore
	if sender.Cmp(amountInt) != 0 || escrow.Cmp(amountInt) != 0 || recipient != 1 {
		t.Fatalf("balance deltas sender=%s escrow=%s recipient=%d, want %s/%s/1 after 10^12 decimal downscaling", sender, escrow, recipient, amount, amount)
	}
	t.Logf("success packet=%s token=%s deltas sender=%s escrow=%s recipient=%d", hash, wrappedToken, sender, escrow, recipient)
}

func TestNoForceEvents(t *testing.T) {
	cfg := loadConfig()
	if !cfg.RunPackets {
		t.Skip("set RUN_PACKET_TESTS=1 to inspect the live full-cycle run")
	}
	for _, eventType := range []string{
		"ForceUpdateClient",
		"ForceConnectionOpenTry", "ForceConnectionOpenAck", "ForceConnectionOpenConfirm",
		"ForceChannelOpenTry", "ForceChannelOpenAck", "ForceChannelOpenConfirm",
	} {
		if txs, err := queryGnoEvents(cfg.Gno.Indexer, eventType, nil); err != nil || len(txs) != 0 {
			t.Fatalf("Gno %s count = %d, want 0: %v", eventType, len(txs), err)
		}
	}
	calls, err := queryGnoForceCalls(cfg.Gno.Indexer)
	if err != nil {
		t.Fatal(err)
	}
	for _, name := range []string{"ForceUpdateClient", "ForceConnectionOpen", "ForceChannelOpen"} {
		if strings.Contains(calls, name) {
			t.Fatalf("Gno run contains %s call: %s", name, calls)
		}
	}

	out, err := dockerExec(cfg.Union.Container, "uniond", "query", "txs",
		"--query", "wasm-force_update_client.client_id EXISTS",
		"--node", "tcp://localhost:26657", "-o", "json", "--limit", "1")
	if err != nil {
		t.Fatalf("query Union ForceUpdateClient events: %v\n%s", err, out)
	}
	var response struct {
		Txs         []json.RawMessage `json:"txs"`
		TxResponses []json.RawMessage `json:"tx_responses"`
	}
	if err := json.Unmarshal([]byte(out), &response); err != nil {
		t.Fatalf("decode Union ForceUpdateClient events: %v\n%s", err, out)
	}
	if len(response.Txs)+len(response.TxResponses) != 0 {
		t.Fatalf("Union ForceUpdateClient count = %d, want 0", len(response.Txs)+len(response.TxResponses))
	}
}

func packetCommitmentPath(t *testing.T, hash string) string {
	t.Helper()
	encoded := mustCommand(t, "cast", "abi-encode", "f(uint256,bytes32)", "4", hash)
	return strings.TrimPrefix(mustCommand(t, "cast", "keccak", encoded), "0x")
}

func waitForUnionMembershipCommit(t *testing.T, cfg config, failedBaseline int64, client string, minProofHeight int64, path string) int64 {
	t.Helper()
	deadline := time.Now().Add(5 * time.Minute)
	var lastErr error
	for time.Now().Before(deadline) {
		heights, err := queryUnionMembershipCommits(cfg.Union, client, minProofHeight, path)
		if err == nil && len(heights) == 1 {
			return heights[0]
		}
		lastErr = err
		if len(heights) > 1 {
			t.Fatalf("Union commit_membership_proof count = %d, want 1", len(heights))
		}
		if rows := voyagerRowsAfter(t, cfg.Voyager, "failed", failedBaseline); rows != "" {
			t.Fatalf("Voyager failed before Union membership commit:\n%s", rows)
		}
		time.Sleep(time.Second)
	}
	t.Fatalf("Union commit_membership_proof client=%s height>=%d path=%s not found: %v", client, minProofHeight, path, lastErr)
	return 0
}

func queryUnionMembershipCommits(cfg unionConfig, client string, minProofHeight int64, path string) ([]int64, error) {
	// Query by client ID, then match the proof path and minimum height locally.
	out, err := dockerExec(cfg.Container, "uniond", "query", "txs", "--query", fmt.Sprintf("wasm-commit_membership_proof.client_id='%s'", client), "--node", "tcp://localhost:26657", "-o", "json", "--limit", "100", "--order_by", "desc")
	if err != nil {
		return nil, err
	}
	type unionEvent struct {
		Type       string                        `json:"type"`
		Attributes []struct{ Key, Value string } `json:"attributes"`
	}
	type unionTx struct {
		Events []unionEvent `json:"events"`
	}
	var response struct {
		Txs         []unionTx `json:"txs"`
		TxResponses []unionTx `json:"tx_responses"`
	}
	if err := json.Unmarshal([]byte(out), &response); err != nil {
		return nil, err
	}
	heights := []int64{}
	for _, tx := range append(response.Txs, response.TxResponses...) {
		for _, event := range tx.Events {
			if event.Type != "wasm-commit_membership_proof" && event.Type != "commit_membership_proof" {
				continue
			}
			attrs := map[string]string{}
			for _, attr := range event.Attributes {
				attrs[attr.Key] = attr.Value
			}
			proofHeight, err := strconv.ParseInt(attrs["proof_height"], 10, 64)
			if err == nil && attrs["client_id"] == client && proofHeight >= minProofHeight && strings.EqualFold(strings.TrimPrefix(attrs["path"], "0x"), path) {
				heights = append(heights, proofHeight)
			}
		}
	}
	return heights, nil
}

func requireNoForbiddenRelayPath(t *testing.T, cfg voyagerConfig, baseline voyagerBaseline) {
	t.Helper()
	for table, id := range map[string]int64{"queue": baseline.Queue, "done": baseline.Done, "failed": baseline.Failed} {
		rows := strings.ToLower(voyagerRowsAfter(t, cfg, table, id))
		if strings.Contains(rows, "force_update_client") || strings.Contains(rows, "intent_packet") {
			t.Fatalf("direct packet used a forbidden relay path in %s:\n%s", table, rows)
		}
	}
}
