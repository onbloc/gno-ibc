package gno

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/onbloc/gno-ibc/e2e/union/internal/config"
	"github.com/onbloc/gno-ibc/e2e/union/internal/process"
)

func TestWaitPacketRequiresOneReceiveAndWriteAckInSameTransaction(t *testing.T) {
	txHash := base64.StdEncoding.EncodeToString(make([]byte, 32))
	packetHash := "0x" + strings.Repeat("a", 64)
	core := "gno.land/r/onbloc/ibc/union/core"
	var requests atomic.Int64
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, request *http.Request) {
		requests.Add(1)
		var body struct {
			Query string `json:"query"`
		}
		if err := json.NewDecoder(request.Body).Decode(&body); err != nil {
			http.Error(w, "bad request", http.StatusBadRequest)
			return
		}
		if !strings.Contains(body.Query, "PacketRecv") {
			http.Error(w, "wrong query", http.StatusBadRequest)
			return
		}
		receiveAttrs := []attribute{{Key: "packet_hash", Value: packetHash}}
		ackAttrs := append([]attribute{}, receiveAttrs...)
		ackAttrs = append(ackAttrs,
			attribute{Key: "acknowledgement_size", Value: "66"},
			attribute{Key: "acknowledgement[1]", Value: "01"},
			attribute{Key: "acknowledgement[0]", Value: "0x" + strings.Repeat("0", 62)},
		)
		fmt.Fprintf(w, `{"data":{"getTransactions":[{"hash":%q,"response":{"events":[`+
			`{"type":"PacketRecv","pkg_path":%q,"attrs":%s},`+
			`{"type":"WriteAck","pkg_path":%q,"attrs":%s}]}}]}}`,
			txHash, core, mustJSON(receiveAttrs), core, mustJSON(ackAttrs))
	}))
	defer server.Close()
	cfg := testConfig()
	cfg.GnoPacketIndexerRPCURL = server.URL
	result, err := NewWithExecutor(cfg, nil).WaitPacket(context.Background(), packetHash)
	if err != nil {
		t.Fatal(err)
	}
	if result.ReceiveTx != txHash || result.WriteAckTx != txHash ||
		result.Acknowledgement != "0x"+strings.Repeat("0", 62)+"01" {
		t.Fatalf("result = %#v", result)
	}
	if requests.Load() != 1 {
		t.Fatalf("indexer requests = %d, want one", requests.Load())
	}
}

func TestWaitPacketRejectsMalformedTransactionHash(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		fmt.Fprint(w, `{"data":{"getTransactions":[{"hash":"bad","response":{"events":[]}}]}}`)
	}))
	defer server.Close()
	cfg := testConfig()
	cfg.GnoPacketIndexerRPCURL = server.URL
	_, err := NewWithExecutor(cfg, nil).WaitPacket(context.Background(), "0x"+strings.Repeat("a", 64))
	if err == nil || !strings.Contains(err.Error(), "transaction hash") {
		t.Fatalf("error = %v", err)
	}
}

func TestWaitPacketCountsWriteAckInAnotherTransaction(t *testing.T) {
	packetHash := "0x" + strings.Repeat("a", 64)
	tx1 := base64.StdEncoding.EncodeToString(make([]byte, 32))
	tx2 := base64.StdEncoding.EncodeToString(bytes.Repeat([]byte{1}, 32))
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		fmt.Fprintf(w, `{"data":{"getTransactions":[`+
			`{"hash":%q,"response":{"events":[`+
			`{"type":"PacketRecv","pkg_path":%q,"attrs":[{"key":"packet_hash","value":%q}]},`+
			`{"type":"WriteAck","pkg_path":%q,"attrs":[{"key":"packet_hash","value":%q}]}]}},`+
			`{"hash":%q,"response":{"events":[`+
			`{"type":"WriteAck","pkg_path":%q,"attrs":[{"key":"packet_hash","value":%q}]}]}}]}}`,
			tx1, testConfig().GnoIBCCoreRealm, packetHash,
			testConfig().GnoIBCCoreRealm, packetHash,
			tx2, testConfig().GnoIBCCoreRealm, packetHash)
	}))
	defer server.Close()
	cfg := testConfig()
	cfg.GnoPacketIndexerRPCURL = server.URL
	_, err := NewWithExecutor(cfg, nil).WaitPacket(context.Background(), packetHash)
	if err == nil || !strings.Contains(err.Error(), "WriteAck count=2") {
		t.Fatalf("error = %v", err)
	}
}

func TestVoucherBalanceRejectsTrailingOutput(t *testing.T) {
	cfg := testConfig()
	client := NewWithExecutor(cfg, executorFunc(func(context.Context, process.Command) (process.Result, error) {
		return process.Result{Stdout: []byte("(1 int64) trailing")}, nil
	}))
	if _, err := client.VoucherBalance(
		context.Background(), "ibc/"+strings.Repeat("8", 40), "g1"+strings.Repeat("a", 38),
	); err == nil {
		t.Fatal("trailing qeval output unexpectedly accepted")
	}
}

func TestVoucherBalanceAcceptsQueryEnvelope(t *testing.T) {
	cfg := testConfig()
	client := NewWithExecutor(cfg, executorFunc(func(context.Context, process.Command) (process.Result, error) {
		return process.Result{Stdout: []byte("height: 0\ndata: (1 int64)\n")}, nil
	}))
	balance, err := client.VoucherBalance(
		context.Background(), "ibc/"+strings.Repeat("8", 40), "g1"+strings.Repeat("a", 38),
	)
	if err != nil {
		t.Fatal(err)
	}
	if balance != 1 {
		t.Fatalf("balance = %d, want 1", balance)
	}
}

func TestProxyAddressAcceptsQEvalAddressType(t *testing.T) {
	cfg := testConfig()
	client := NewWithExecutor(cfg, executorFunc(func(context.Context, process.Command) (process.Result, error) {
		return process.Result{Stdout: []byte(
			`height: 0` + "\n" + `data: ("g182p37d0cyvsvqpv49lqtphpj3jswwqtuyl4qyy" .uverse.address)`,
		)}, nil
	}))
	address, err := client.ProxyAddress(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if address != "g182p37d0cyvsvqpv49lqtphpj3jswwqtuyl4qyy" {
		t.Fatalf("address = %s", address)
	}
}

func TestNativeBalanceMatchesExactDenom(t *testing.T) {
	cfg := testConfig()
	client := NewWithExecutor(cfg, executorFunc(func(context.Context, process.Command) (process.Result, error) {
		return process.Result{Stdout: []byte(`data: "1myugnot, 2ugnot"`)}, nil
	}))
	balance, err := client.NativeBalance(context.Background(), DevSenderAddress, "ugnot")
	if err != nil {
		t.Fatal(err)
	}
	if balance != 2 {
		t.Fatalf("balance = %d, want 2", balance)
	}
}

func TestSendRawUsesDevEOAAndReturnsNewPacket(t *testing.T) {
	txHash := base64.StdEncoding.EncodeToString(make([]byte, 32))
	packetHash := "0x" + strings.Repeat("a", 64)
	var requests atomic.Int64
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		if requests.Add(1) == 1 {
			fmt.Fprint(w, `{"data":{"getTransactions":[]}}`)
			return
		}
		fmt.Fprintf(w, `{"data":{"getTransactions":[{"hash":%q,"block_height":2,`+
			`"response":{"events":[{"type":"PacketSend","pkg_path":%q,"attrs":[`+
			`{"key":"source_channel_id","value":"3"},{"key":"packet_hash","value":%q}]}]}}]}}`,
			txHash, testConfig().GnoIBCCoreRealm, packetHash)
	}))
	defer server.Close()
	cfg := testConfig()
	cfg.GnoPacketIndexerRPCURL = server.URL
	cfg.GnoRecipient = "g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5"
	cfg.GnoChainID = "dev.ibc"
	var commands []process.Command
	outputs := [][]byte{
		nil,
		[]byte("0. sender (local) - addr: " + cfg.GnoRecipient + " pub: key"),
		nil,
	}
	client := NewWithExecutor(cfg, executorFunc(func(_ context.Context, command process.Command) (process.Result, error) {
		commands = append(commands, command)
		output := outputs[0]
		outputs = outputs[1:]
		return process.Result{Stdout: output}, nil
	}))
	send, err := client.SendRaw(context.Background(), 3, "0x01", "1ugnot")
	if err != nil {
		t.Fatal(err)
	}
	if send.PacketHash != packetHash || len(commands) != 3 {
		t.Fatalf("send = %#v, commands = %d", send, len(commands))
	}
	if commands[0].Stdin == nil || commands[2].Stdin == nil ||
		!strings.Contains(strings.Join(commands[2].Args, " "), "SendRaw") {
		t.Fatalf("gnokey commands = %#v", commands)
	}
}

func TestParseAcknowledgementRejectsMalformedKeys(t *testing.T) {
	for _, attrs := range [][]attribute{
		{
			{Key: "acknowledgement", Value: ""},
			{Key: "acknowledgement", Value: "0x00"},
		},
		{
			{Key: "acknowledgement_size", Value: "4"},
			{Key: "acknowledgement[999999999999999999999999]", Value: "0x00"},
		},
	} {
		if _, err := parseAcknowledgement(attrs); err == nil {
			t.Fatalf("malformed attributes unexpectedly passed: %#v", attrs)
		}
	}
}

type executorFunc func(context.Context, process.Command) (process.Result, error)

func (f executorFunc) Run(ctx context.Context, command process.Command) (process.Result, error) {
	return f(ctx, command)
}

func testConfig() config.Config {
	return config.Config{
		GnoIBCCoreRealm:        "gno.land/r/onbloc/ibc/union/core",
		GnoZKGMPort:            "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm",
		GnoPacketRPCURL:        "https://gno.example",
		GnoPacketIndexerRPCURL: "https://indexer.example",
		CommandTimeout:         time.Second,
		ScenarioTimeout:        time.Second,
		PollInterval:           0,
	}
}

func mustJSON(value any) string {
	data, _ := json.Marshal(value)
	return string(data)
}
