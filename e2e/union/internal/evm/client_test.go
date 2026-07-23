package evm

import (
	"context"
	"encoding/json"
	"errors"
	"strings"
	"testing"
	"time"

	"github.com/onbloc/gno-ibc/e2e/union/internal/config"
	"github.com/onbloc/gno-ibc/e2e/union/internal/process"
)

func TestSendExtractsOnePacketForExpectedChannel(t *testing.T) {
	cfg := testConfig()
	packetHash := "0x" + strings.Repeat("b", 64)
	txHash := "0x" + strings.Repeat("a", 64)
	channelTopic := "0x" + strings.Repeat("0", 63) + "7"
	receipt, _ := json.Marshal(transactionReceipt{
		Status: "0x1", TransactionHash: txHash,
		Logs: []evmLog{{
			Address: cfg.EVMIBCHandler,
			Topics:  []string{packetSendTopic, channelTopic, packetHash},
		}},
	})
	executor := &fakeExecutor{outputs: [][]byte{
		[]byte("0x01"), []byte("0x02"), []byte("0x03"), receipt,
	}}
	client := NewWithExecutor(cfg, executor)
	result, err := client.Send(
		context.Background(), 7,
		"0x7777777777777777777777777777777777777777",
		"g1"+strings.Repeat("a", 38), "ibc/"+strings.Repeat("8", 40),
		"0x"+strings.Repeat("9", 64), strings.Repeat("9", 64),
	)
	if err != nil {
		t.Fatal(err)
	}
	if result.Tx != txHash || result.PacketHash != packetHash {
		t.Fatalf("result = %#v", result)
	}
	if got := executor.commands[0].Args; !strings.Contains(
		strings.Join(got, " "),
		"f(address,address,string,string,uint8) 0x7777777777777777777777777777777777777777 "+
			cfg.EVMZKGMContract,
	) {
		t.Fatalf("initializer command = %q", got)
	}
	if got := executor.commands[1].Args; got[len(got)-1] != "0x8420ce9901" {
		t.Fatalf("initializer = %q, want selector-prefixed calldata", got[len(got)-1])
	}
}

func TestSendRejectsDuplicatePacketSend(t *testing.T) {
	cfg := testConfig()
	log := func(channel string) evmLog {
		return evmLog{
			Address: cfg.EVMIBCHandler,
			Topics: []string{
				packetSendTopic, "0x" + strings.Repeat("0", 63) + channel,
				"0x" + strings.Repeat("b", 64),
			},
		}
	}
	receipt, _ := json.Marshal(transactionReceipt{
		Status: "0x1", TransactionHash: "0x" + strings.Repeat("a", 64),
		Logs: []evmLog{log("1"), log("2")},
	})
	client := NewWithExecutor(cfg, &fakeExecutor{outputs: [][]byte{
		[]byte("0x01"), []byte("0x02"), []byte("0x03"), receipt,
	}})
	_, err := client.Send(
		context.Background(), 1,
		"0x7777777777777777777777777777777777777777",
		"g1"+strings.Repeat("a", 38), "ibc/"+strings.Repeat("8", 40),
		"0x"+strings.Repeat("9", 64), strings.Repeat("9", 64),
	)
	if err == nil || !strings.Contains(err.Error(), "count is not one") {
		t.Fatalf("error = %v", err)
	}
}

func TestSendCountsMalformedPacketSendBeforeValidation(t *testing.T) {
	cfg := testConfig()
	packetHash := "0x" + strings.Repeat("b", 64)
	receipt, _ := json.Marshal(transactionReceipt{
		Status: "0x1", TransactionHash: "0x" + strings.Repeat("a", 64),
		Logs: []evmLog{
			{
				Address: cfg.EVMIBCHandler,
				Topics: []string{
					packetSendTopic, "0x" + strings.Repeat("0", 63) + "1", packetHash,
				},
			},
			{Address: cfg.EVMIBCHandler, Topics: []string{packetSendTopic}},
		},
	})
	client := NewWithExecutor(cfg, &fakeExecutor{outputs: [][]byte{
		[]byte("0x01"), []byte("0x02"), []byte("0x03"), receipt,
	}})
	_, err := client.Send(
		context.Background(), 1,
		"0x7777777777777777777777777777777777777777",
		"g1"+strings.Repeat("a", 38), "ibc/"+strings.Repeat("8", 40),
		"0x"+strings.Repeat("9", 64), strings.Repeat("9", 64),
	)
	if err == nil || !strings.Contains(err.Error(), "count is not one") {
		t.Fatalf("error = %v", err)
	}
}

func TestWaitAcknowledgementRevalidatesReturnedLog(t *testing.T) {
	cfg := testConfig()
	cfg.PollInterval = 0
	logs, _ := json.Marshal([]evmLog{{
		Address:         "0x9999999999999999999999999999999999999999",
		Topics:          []string{packetAckTopic, "0x" + strings.Repeat("0", 64), "0x" + strings.Repeat("b", 64)},
		Data:            "0x00",
		TransactionHash: "0x" + strings.Repeat("a", 64),
	}})
	client := NewWithExecutor(cfg, &fakeExecutor{outputs: [][]byte{logs}})
	_, err := client.WaitAcknowledgement(
		context.Background(), 1, 1, "0x"+strings.Repeat("b", 64),
	)
	if err == nil || !strings.Contains(err.Error(), "malformed EVM PacketAck log") {
		t.Fatalf("error = %v", err)
	}
}

func TestBalancesPreserveLargeDecimals(t *testing.T) {
	cfg := testConfig()
	large := "100000000000000000000000000000000000000"
	client := NewWithExecutor(cfg, &fakeExecutor{outputs: [][]byte{[]byte(large), []byte("0")}})
	sender, escrow, err := client.Balances(context.Background(), "0x7777777777777777777777777777777777777777")
	if err != nil {
		t.Fatal(err)
	}
	if sender != large || escrow != "0" {
		t.Fatalf("balances = %s, %s", sender, escrow)
	}
}

func TestPrepareValidatesTokenCodeAndDecimals(t *testing.T) {
	sender := []byte("0x7777777777777777777777777777777777777777")
	for _, tc := range []struct {
		name    string
		outputs [][]byte
		wantErr string
	}{
		{"missing code", [][]byte{sender, []byte("0x")}, "no deployed code"},
		{"wrong decimals", [][]byte{sender, []byte("0x01"), []byte("6")}, "18 decimals"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			_, err := NewWithExecutor(testConfig(), &fakeExecutor{outputs: tc.outputs}).
				Prepare(context.Background(), 1)
			if err == nil || !strings.Contains(err.Error(), tc.wantErr) {
				t.Fatalf("error = %v", err)
			}
		})
	}
}

type fakeExecutor struct {
	outputs  [][]byte
	commands []process.Command
	err      error
}

func (f *fakeExecutor) Run(_ context.Context, command process.Command) (process.Result, error) {
	f.commands = append(f.commands, command)
	if f.err != nil {
		return process.Result{}, f.err
	}
	if len(f.outputs) == 0 {
		return process.Result{}, errors.New("unexpected command")
	}
	output := f.outputs[0]
	f.outputs = f.outputs[1:]
	return process.Result{Stdout: output}, nil
}

func testConfig() config.Config {
	return config.Config{
		EVMIBCHandler:   "0x1111111111111111111111111111111111111111",
		EVMZKGMContract: "0x5555555555555555555555555555555555555555",
		EVMTestERC20:    "0x6666666666666666666666666666666666666666",
		EVMTestAmount:   "1000000000000",
		EVMPrivateKey:   "0x" + strings.Repeat("c", 64),
		EVMPacketRPCURL: "https://evm.example",
		CommandTimeout:  time.Second,
		ScenarioTimeout: time.Second,
		PollInterval:    0,
	}
}
