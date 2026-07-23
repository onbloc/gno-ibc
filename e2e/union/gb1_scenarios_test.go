package unione2e

import (
	"context"
	"fmt"
	"math/big"
	"os/exec"
	"strconv"
	"strings"
	"testing"
	"time"
)

func TestTokenOrderInitializeEscrowUnescrowLifecycle(t *testing.T) {
	h := newBridgeHarness(t)
	requireGnoEVMDirectTopology(t, h.cfg)

	const amount = "1"
	tag := fmt.Sprintf("%09d", time.Now().UnixNano()%1_000_000_000)
	metadata := tokenMetadata{name: "GB1 Lifecycle " + tag, symbol: "GB1" + tag[len(tag)-3:], decimals: 6}
	encodedMetadata := evmMetadata(t, h.cfg.EVM, metadata)
	wrappedToken := predictEVMWrappedToken(t, h.cfg.EVM, h.cfg.Topology.EVMGno.ChannelID, []byte("ugnot"), encodedMetadata)
	firstEVMBlock, err := queryEVMBlockNumber(h.cfg.EVM.RPC)
	firstEVMBlock = must(t, firstEVMBlock, err)
	queryNativeBalance := func(owner string) int64 {
		t.Helper()
		ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()
		cmd := exec.CommandContext(ctx, "docker", "compose", "exec", "-T", "gno",
			"gnokey", "query", "bank/balances/"+owner, "-remote", "localhost:26657")
		cmd.Dir = h.cfg.Gno.ComposeDir
		out, err := cmd.CombinedOutput()
		if err != nil {
			t.Fatalf("query Gno balance failed: %v\n%s", err, out)
		}
		for _, line := range strings.Split(string(out), "\n") {
			line = strings.TrimSpace(line)
			if !strings.HasPrefix(line, `data: "`) {
				continue
			}
			for _, coin := range strings.Split(strings.TrimSuffix(strings.TrimPrefix(line, `data: "`), `"`), ",") {
				if strings.HasSuffix(coin, "ugnot") {
					amount, err := strconv.ParseInt(strings.TrimSuffix(coin, "ugnot"), 10, 64)
					return must(t, amount, err)
				}
			}
			return 0
		}
		t.Fatalf("parse Gno balance response: %s", out)
		return 0
	}
	var proxyAddress string
	for _, line := range strings.Split(queryGnoQEval(t, h.cfg.Gno, "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm.ProxyAddress()"), "\n") {
		if line = strings.TrimSpace(line); strings.HasPrefix(line, "data: (") {
			proxyAddress = strings.Trim(strings.Fields(strings.TrimPrefix(line, "data: ("))[0], `"`)
			break
		}
	}
	if proxyAddress == "" {
		t.Fatal("Gno ZKGM proxy address is empty")
	}
	proxyBefore := queryNativeBalance(proxyAddress)

	sendAndRequireGnoOrderRoundTrip := func(kind uint8) string {
		t.Helper()
		order := encodeTokenOrder(t, tokenOrder{
			Sender: asciiHex(h.cfg.Gno.Sender), Receiver: h.evmSender, BaseToken: asciiHex("ugnot"),
			QuoteToken: wrappedToken, Metadata: encodedMetadata, Amount: amount, Kind: kind,
		})
		baseline := captureVoyagerBaseline(t, h.cfg.Voyager)
		evmFrom, err := queryEVMBlockNumber(h.cfg.EVM.RPC)
		evmFrom = must(t, evmFrom, err)
		after := latestGnoEventHeight(h.cfg.Gno.Indexer, "PacketSend", map[string]string{"source_channel_id": h.cfg.Topology.GnoEVM.ChannelID})
		broadcastGnoPacket(t, h.cfg.Gno, h.cfg.Topology.GnoEVM.ChannelID, order, "1ugnot", randomHex32(t), time.Now().Add(time.Hour).UnixNano())
		send := waitForNewGnoEvent(t, h.cfg, "PacketSend", map[string]string{"source_channel_id": h.cfg.Topology.GnoEVM.ChannelID}, after, baseline)
		hash := txAttr(send, "PacketSend", "packet_hash")
		requireOneGnoEvent(t, h.cfg.Gno, "PacketSend", hash)

		path := packetCommitmentPath(t, hash)
		waitForUnionMembershipCommit(t, h.cfg, baseline.Failed, h.cfg.Topology.UnionGno.ClientID, send.BlockHeight+1, path)
		recv := waitForEVMLog(t, h.cfg, baseline.Failed, h.cfg.EVM.IBCHandler, packetRecvTopic, evmFrom+1, topicUint32(mustUint32(t, h.cfg.Topology.EVMGno.ChannelID)), hash)
		write := waitForEVMLog(t, h.cfg, baseline.Failed, h.cfg.EVM.IBCHandler, writeAckTopic, evmFrom+1, topicUint32(mustUint32(t, h.cfg.Topology.EVMGno.ChannelID)), hash)
		requireEVMReceiveAndAck(t, h.cfg, evmFrom+1, h.cfg.Topology.EVMGno.ChannelID, hash, recv, write)

		waitForNewGnoEvent(t, h.cfg, "PacketAck", map[string]string{"packet_hash": hash}, send.BlockHeight, baseline)
		requireOneGnoEvent(t, h.cfg.Gno, "PacketAck", hash)
		requireGnoPacketAcknowledged(t, h.cfg.Gno, hash)
		requirePacketVoyagerSuccess(t, h.cfg.Voyager, baseline, hash)
		requireNoForbiddenRelayPath(t, h.cfg.Voyager, baseline)
		return hash
	}

	initializeHash := sendAndRequireGnoOrderRoundTrip(tokenOrderKindInitialize)
	if code, err := queryEVMCode(h.cfg.EVM.RPC, wrappedToken); err != nil || len(code) == 0 {
		t.Fatalf("EVM wrapped token %s was not created: %v", wrappedToken, err)
	}
	createLogs, err := queryEVMLogs(h.cfg.EVM.RPC, h.cfg.EVM.ZKGM, firstEVMBlock+1, createWrappedTokenTopic, topicUint32(mustUint32(t, h.cfg.Topology.EVMGno.ChannelID)), topicAddress(wrappedToken))
	if err != nil || len(createLogs) != 1 {
		t.Fatalf("INITIALIZE CreateWrappedToken count = %d, want 1: %v", len(createLogs), err)
	}
	if balance := queryERC20Balance(t, h.cfg.EVM, wrappedToken, h.evmSender); balance.Cmp(big.NewInt(1)) != 0 {
		t.Fatalf("wrapped balance after INITIALIZE = %s, want 1", balance)
	}
	if supply := queryERC20TotalSupply(t, h.cfg.EVM, wrappedToken); supply.Cmp(big.NewInt(1)) != 0 {
		t.Fatalf("wrapped total supply after INITIALIZE = %s, want 1", supply)
	}
	if proxy := queryNativeBalance(proxyAddress); proxy-proxyBefore != 1 {
		t.Fatalf("Gno proxy balance delta after INITIALIZE = %d, want 1", proxy-proxyBefore)
	}

	escrowHash := sendAndRequireGnoOrderRoundTrip(tokenOrderKindEscrow)
	createLogs, err = queryEVMLogs(h.cfg.EVM.RPC, h.cfg.EVM.ZKGM, firstEVMBlock+1, createWrappedTokenTopic, topicUint32(mustUint32(t, h.cfg.Topology.EVMGno.ChannelID)), topicAddress(wrappedToken))
	if err != nil || len(createLogs) != 1 {
		t.Fatalf("CreateWrappedToken count after ESCROW = %d, want 1: %v", len(createLogs), err)
	}
	if balance := queryERC20Balance(t, h.cfg.EVM, wrappedToken, h.evmSender); balance.Cmp(big.NewInt(2)) != 0 {
		t.Fatalf("wrapped balance after ESCROW = %s, want 2", balance)
	}
	if supply := queryERC20TotalSupply(t, h.cfg.EVM, wrappedToken); supply.Cmp(big.NewInt(2)) != 0 {
		t.Fatalf("wrapped total supply after ESCROW = %s, want 2", supply)
	}
	if proxy := queryNativeBalance(proxyAddress); proxy-proxyBefore != 2 {
		t.Fatalf("Gno proxy balance delta after ESCROW = %d, want 2", proxy-proxyBefore)
	}

	castSend(t, h.cfg.EVM, wrappedToken, "approve(address,uint256)", h.cfg.EVM.ZKGM, amount)
	gnoBefore := queryNativeBalance(h.cfg.Gno.Sender)
	operand := encodeTokenOrder(t, tokenOrder{
		Sender: h.evmSender, Receiver: asciiHex(h.cfg.Gno.Sender), BaseToken: wrappedToken,
		QuoteToken: asciiHex("ugnot"), Metadata: "0x", Amount: amount, Kind: tokenOrderKindUnescrow,
	})
	baseline := captureVoyagerBaseline(t, h.cfg.Voyager)
	evmFrom, err := queryEVMBlockNumber(h.cfg.EVM.RPC)
	evmFrom = must(t, evmFrom, err)
	receipt := broadcastEVMPacket(t, h.cfg.EVM, h.cfg.Topology.EVMGno.ChannelID, operand, time.Now().Add(time.Hour).UnixNano())
	unescrowHash := evmPacketHashFromReceipt(t, h.cfg.EVM, receipt)

	recv := waitForGnoEvent(t, h.cfg.Gno.Indexer, "PacketRecv", map[string]string{"packet_hash": unescrowHash})
	write := waitForGnoEvent(t, h.cfg.Gno.Indexer, "WriteAck", map[string]string{"packet_hash": unescrowHash})
	requireOneGnoEvent(t, h.cfg.Gno, "PacketRecv", unescrowHash)
	requireOneGnoEvent(t, h.cfg.Gno, "WriteAck", unescrowHash)
	if recv.Hash != write.Hash || ackTag(mustDecodeHex(t, txEncodedAttr(write, "WriteAck", "acknowledgement"))) != 1 {
		t.Fatalf("Gno receive/write acknowledgement is not one successful transaction: recv=%s write=%s", recv.Hash, write.Hash)
	}

	ack := waitForEVMLog(t, h.cfg, baseline.Failed, h.cfg.EVM.IBCHandler, evmPacketAckTopic, evmFrom+1, topicUint32(mustUint32(t, h.cfg.Topology.EVMGno.ChannelID)), unescrowHash)
	ackBytes, err := abiBytes(mustDecodeHex(t, ack.Data), 0)
	if err != nil || ackTag(ackBytes) != 1 {
		t.Fatalf("EVM PacketAck is not success: %v", err)
	}
	if logs, err := queryEVMLogs(h.cfg.EVM.RPC, h.cfg.EVM.IBCHandler, evmFrom+1, evmPacketAckTopic, topicUint32(mustUint32(t, h.cfg.Topology.EVMGno.ChannelID)), unescrowHash); err != nil || len(logs) != 1 {
		t.Fatalf("EVM PacketAck count = %d, want 1: %v", len(logs), err)
	}
	requireEVMPacketInactive(t, h.cfg.EVM, unescrowHash)
	requirePacketVoyagerSuccess(t, h.cfg.Voyager, baseline, unescrowHash)
	requireNoForbiddenRelayPath(t, h.cfg.Voyager, baseline)

	if balance := queryERC20Balance(t, h.cfg.EVM, wrappedToken, h.evmSender); balance.Cmp(big.NewInt(1)) != 0 {
		t.Fatalf("wrapped balance after UNESCROW = %s, want 1", balance)
	}
	if supply := queryERC20TotalSupply(t, h.cfg.EVM, wrappedToken); supply.Cmp(big.NewInt(1)) != 0 {
		t.Fatalf("wrapped total supply after UNESCROW = %s, want 1", supply)
	}
	if gnoAfter := queryNativeBalance(h.cfg.Gno.Sender); gnoAfter-gnoBefore != 1 {
		t.Fatalf("Gno native balance delta after UNESCROW = %d, want 1", gnoAfter-gnoBefore)
	}
	if proxy := queryNativeBalance(proxyAddress); proxy-proxyBefore != 1 {
		t.Fatalf("Gno proxy balance delta after UNESCROW = %d, want 1", proxy-proxyBefore)
	}
	t.Logf("lifecycle packets INITIALIZE=%s ESCROW=%s UNESCROW=%s token=%s", initializeHash, escrowHash, unescrowHash, wrappedToken)
}
