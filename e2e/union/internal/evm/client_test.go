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
		"f(address,address,string,string,uint8) "+
			"0x0000000000000000000000000000000000000000 "+
			"0x0000000000000000000000000000000000000000 Union E2E ",
	) {
		t.Fatalf("initializer command = %q", got)
	}
	if got := executor.commands[1].Args; got[len(got)-1] != "0x8420ce9901" {
		t.Fatalf("initializer = %q, want ZkgmERC20 calldata", got[len(got)-1])
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

func TestNativeRelayerBalanceAndFunding(t *testing.T) {
	txHash := "0x" + strings.Repeat("a", 64)
	receipt, _ := json.Marshal(transactionReceipt{Status: "0x1", TransactionHash: txHash})
	executor := &fakeExecutor{outputs: [][]byte{
		[]byte("0x7777777777777777777777777777777777777777"), []byte("42"), receipt,
	}}
	client := NewWithExecutor(testConfig(), executor)
	address, err := client.Address(context.Background(), "0x"+strings.Repeat("1", 64))
	if err != nil {
		t.Fatal(err)
	}
	balance, err := client.NativeBalance(context.Background(), address)
	if err != nil || balance.String() != "42" {
		t.Fatalf("balance = %v, %v", balance, err)
	}
	got, err := client.FundNative(context.Background(), address, "100")
	if err != nil || got != txHash {
		t.Fatalf("fund = %q, %v", got, err)
	}
	if command := strings.Join(executor.commands[2].Args, " "); !strings.Contains(command, "send "+address+" --value 100 --private-key") {
		t.Fatalf("fund command = %q", command)
	}
}

func TestTransactionSender(t *testing.T) {
	executor := &fakeExecutor{outputs: [][]byte{[]byte(`{"from":"0x7777777777777777777777777777777777777777"}`)}}
	sender, err := NewWithExecutor(testConfig(), executor).TransactionSender(
		context.Background(), "0x"+strings.Repeat("a", 64),
	)
	if err != nil || sender != "0x7777777777777777777777777777777777777777" {
		t.Fatalf("sender = %q, %v", sender, err)
	}
}

func TestSetZKGMPausedOnlySendsWhenStateChanges(t *testing.T) {
	cfg := testConfig()
	txHash := "0x" + strings.Repeat("a", 64)
	receipt, _ := json.Marshal(transactionReceipt{Status: "0x1", TransactionHash: txHash})
	executor := &fakeExecutor{outputs: [][]byte{[]byte("false"), receipt, []byte("true")}}
	client := NewWithExecutor(cfg, executor)
	got, err := client.SetZKGMPaused(context.Background(), true)
	if err != nil || got != txHash {
		t.Fatalf("pause = %q, %v", got, err)
	}
	got, err = client.SetZKGMPaused(context.Background(), true)
	if err != nil || got != "" {
		t.Fatalf("idempotent pause = %q, %v", got, err)
	}
	if len(executor.commands) != 3 ||
		!strings.Contains(strings.Join(executor.commands[1].Args, " "), "pause() --private-key") {
		t.Fatalf("commands = %#v", executor.commands)
	}
}

func TestChannelMembershipUsesOpenTopology(t *testing.T) {
	path := "0x" + strings.Repeat("a", 64)
	value := "0x" + strings.Repeat("b", 64)
	commitment := "0x" + strings.Repeat("c", 64)
	executor := &fakeExecutor{outputs: [][]byte{
		[]byte("0x01"), []byte(path), []byte("0x02"), []byte(value), []byte(commitment),
	}}
	got, err := NewWithExecutor(testConfig(), executor).ChannelMembership(
		context.Background(), 7, 8, 9, "gno.land/r/example/app", "ucs03-zkgm-0",
	)
	if err != nil {
		t.Fatal(err)
	}
	if got.Path != path || got.Value != value || got.Commitment != commitment {
		t.Fatalf("membership = %#v", got)
	}
	commands := make([]string, len(executor.commands))
	for i := range executor.commands {
		commands[i] = strings.Join(executor.commands[i].Args, " ")
	}
	if !strings.Contains(commands[0], "abi-encode f(uint256,uint256) 3 7") ||
		!strings.Contains(commands[2],
			"abi-encode f((uint8,uint32,uint32,bytes,string)) "+
				"(3,8,9,0x676e6f2e6c616e642f722f6578616d706c652f617070,ucs03-zkgm-0)") ||
		!strings.Contains(commands[4], "keccak "+value) {
		t.Fatalf("commands = %#v", commands)
	}
}

func TestSendTokenOrderPreservesAmountAndKind(t *testing.T) {
	cfg := testConfig()
	packetHash := "0x" + strings.Repeat("b", 64)
	txHash := "0x" + strings.Repeat("a", 64)
	receipt, _ := json.Marshal(transactionReceipt{
		Status: "0x1", TransactionHash: txHash,
		Logs: []evmLog{{
			Address: cfg.EVMIBCHandler,
			Topics: []string{
				packetSendTopic, "0x" + strings.Repeat("0", 63) + "7", packetHash,
			},
		}},
	})
	executor := &fakeExecutor{outputs: [][]byte{[]byte("0x01"), receipt}}
	client := NewWithExecutor(cfg, executor)
	_, err := client.SendTokenOrder(context.Background(), 7, Plan{
		Token:   "0x6666666666666666666666666666666666666666",
		Sender:  "0x7777777777777777777777777777777777777777",
		Voucher: "ibc/" + strings.Repeat("8", 40),
		Salt:    "0x" + strings.Repeat("9", 64), Metadata: "0x05",
	}, "g1"+strings.Repeat("a", 38), "9223372036854775808", 1)
	if err != nil {
		t.Fatal(err)
	}
	args := executor.commands[0].Args
	if args[5] != "9223372036854775808" ||
		args[7] != "9223372036854775808" || args[8] != "1" {
		t.Fatalf("TokenOrder amount/kind args = %q", args)
	}
}

func TestSendTokenOrderWithTimeoutUsesExplicitTimestamp(t *testing.T) {
	cfg := testConfig()
	packetHash := "0x" + strings.Repeat("b", 64)
	receipt, _ := json.Marshal(transactionReceipt{
		Status: "0x1", TransactionHash: "0x" + strings.Repeat("a", 64),
		Logs: []evmLog{{
			Address: cfg.EVMIBCHandler,
			Topics: []string{
				packetSendTopic, "0x" + strings.Repeat("0", 63) + "7", packetHash,
			},
		}},
	})
	executor := &fakeExecutor{outputs: [][]byte{[]byte("0x01"), receipt}}
	_, err := NewWithExecutor(cfg, executor).SendTokenOrderWithTimeout(
		context.Background(), 7,
		Plan{
			Token:   "0x6666666666666666666666666666666666666666",
			Sender:  "0x7777777777777777777777777777777777777777",
			Voucher: "ibc/" + strings.Repeat("8", 40), Salt: "0x" + strings.Repeat("9", 64),
			Metadata: "0x05",
		},
		"g1"+strings.Repeat("a", 38), "1", 0, 123456789,
	)
	if err != nil {
		t.Fatal(err)
	}
	if got := strings.Join(executor.commands[1].Args, " "); !strings.Contains(got, "send(uint32,uint64,uint64,bytes32,(uint8,uint8,bytes)) 7 0 123456789 ") {
		t.Fatalf("send command = %q", got)
	}
}

func TestWaitTimeoutRejectsAcknowledgement(t *testing.T) {
	cfg := testConfig()
	packetHash := "0x" + strings.Repeat("b", 64)
	channelTopic := "0x" + strings.Repeat("0", 63) + "7"
	for _, tc := range []struct {
		name    string
		topic   string
		wantErr string
	}{
		{"timeout", packetTimeoutTopic, ""},
		{"acknowledgement", packetAckTopic, "acknowledged instead"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			logs, _ := json.Marshal([]evmLog{{
				Address:         cfg.EVMIBCHandler,
				Topics:          []string{tc.topic, channelTopic, packetHash},
				TransactionHash: "0x" + strings.Repeat("a", 64),
			}})
			result, err := NewWithExecutor(cfg, &fakeExecutor{outputs: [][]byte{logs}}).
				WaitTimeout(context.Background(), 1, 7, packetHash)
			if tc.wantErr == "" {
				if err != nil || result.Tx == "" {
					t.Fatalf("result = %#v, error = %v", result, err)
				}
			} else if err == nil || !strings.Contains(err.Error(), tc.wantErr) {
				t.Fatalf("error = %v", err)
			}
		})
	}
}

func TestPacketReceiveCount(t *testing.T) {
	packetHash := "0x" + strings.Repeat("b", 64)
	executor := &fakeExecutor{outputs: [][]byte{[]byte("[]")}}
	count, err := NewWithExecutor(testConfig(), executor).PacketReceiveCount(
		context.Background(), 12, 7, packetHash,
	)
	if err != nil || count != 0 {
		t.Fatalf("count = %d, %v", count, err)
	}
	command := strings.Join(executor.commands[0].Args, " ")
	if !strings.Contains(command, `"fromBlock":"0xc"`) || !strings.Contains(command, packetHash) {
		t.Fatalf("command = %q", command)
	}
}

func TestDeployTestTokenUsesRepositoryFixture(t *testing.T) {
	cfg := testConfig()
	cfg.ScriptDir = "/repo/e2e/union"
	executor := &fakeExecutor{outputs: [][]byte{
		[]byte(`{"deployedTo":"0x6666666666666666666666666666666666666666"}`),
	}}
	token, err := NewWithExecutor(cfg, executor).
		DeployTestToken(context.Background(), "Boundary", "BDY", 6)
	if err != nil {
		t.Fatal(err)
	}
	if token != "0x6666666666666666666666666666666666666666" {
		t.Fatalf("token = %s", token)
	}
	command := strings.Join(executor.commands[0].Args, " ")
	if !strings.Contains(command, "--root /repo/e2e/union") ||
		!strings.Contains(command, "fixtures/TestERC20.sol:TestERC20") {
		t.Fatalf("forge command = %q", command)
	}
}

func TestPrepareWrappedTokenUsesLiveImplementations(t *testing.T) {
	cfg := testConfig()
	executor := &fakeExecutor{outputs: [][]byte{
		[]byte("0x7777777777777777777777777777777777777777"),
		[]byte("0x8888888888888888888888888888888888888888"),
		[]byte("0x9999999999999999999999999999999999999999"),
		[]byte("0x01"),
		[]byte("0x02"),
		[]byte(`["0x99","0x01"]`),
		[]byte("0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa 0x" + strings.Repeat("0", 64)),
	}}
	plan, err := NewWithExecutor(cfg, executor).
		PrepareWrappedToken(context.Background(), 7, "ugnot")
	if err != nil {
		t.Fatal(err)
	}
	if plan.Token != "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" {
		t.Fatalf("wrapped token = %s", plan.Token)
	}
	if got := strings.Join(executor.commands[6].Args, " "); !strings.Contains(
		got, "predictWrappedTokenV2") || !strings.Contains(got, " 7 0x75676e6f74 ") {
		t.Fatalf("prediction command = %q", got)
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
