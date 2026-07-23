package scenario

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/hex"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/onbloc/gno-ibc/e2e/union/internal/config"
	"github.com/onbloc/gno-ibc/e2e/union/internal/evm"
	"github.com/onbloc/gno-ibc/e2e/union/internal/gno"
	"github.com/onbloc/gno-ibc/e2e/union/internal/process"
	"github.com/onbloc/gno-ibc/e2e/union/internal/state"
	"github.com/onbloc/gno-ibc/e2e/union/internal/voyager"
)

func TestAcknowledgementClassification(t *testing.T) {
	success := encodedAcknowledgement(1, []byte{0xab, 0xcd})
	failure := encodedAcknowledgement(0, nil)
	if got, err := matchingAcknowledgementResult(success, success); err != nil || !got {
		t.Fatalf("success = %v, %v", got, err)
	}
	if got, err := matchingAcknowledgementResult(failure, failure); err != nil || got {
		t.Fatalf("failure = %v, %v", got, err)
	}
	if _, err := matchingAcknowledgementResult(success, failure); err == nil {
		t.Fatal("mismatched acknowledgement results unexpectedly passed")
	}
	if _, err := matchingAcknowledgementResult("0x01", "0x01"); err == nil {
		t.Fatal("short acknowledgement unexpectedly passed")
	}
	for _, malformed := range []string{
		"0x01" + strings.Repeat("0", 62),
		encodedAcknowledgement(2, nil),
		success + "00",
	} {
		if _, err := matchingAcknowledgementResult(malformed, malformed); err == nil {
			t.Fatalf("noncanonical acknowledgement %q unexpectedly passed", malformed)
		}
	}
}

func encodedAcknowledgement(tag byte, payload []byte) string {
	tagWord := make([]byte, 32)
	tagWord[31] = tag
	offsetWord := make([]byte, 32)
	offsetWord[31] = 64
	lengthWord := make([]byte, 32)
	lengthWord[31] = byte(len(payload))
	padded := make([]byte, (len(payload)+31)/32*32)
	copy(padded, payload)
	return "0x" + hex.EncodeToString(append(append(append(tagWord, offsetWord...), lengthWord...), padded...))
}

func TestPacketBalanceClassification(t *testing.T) {
	tests := []struct {
		name    string
		success bool
		before  state.Balances
		after   state.Balances
		wantErr string
	}{
		{
			name: "success", success: true,
			before: state.Balances{Sender: "2000000000000", Escrow: "0", Recipient: "4"},
			after:  state.Balances{Sender: "1000000000000", Escrow: "1000000000000", Recipient: "5"},
		},
		{
			name:   "failure refund",
			before: state.Balances{Sender: "1000000000000", Escrow: "0", Recipient: "4"},
			after:  state.Balances{Sender: "1000000000000", Escrow: "0", Recipient: "4"},
		},
		{
			name: "bad success delta", success: true,
			before:  state.Balances{Sender: "2000000000000", Escrow: "0", Recipient: "4"},
			after:   state.Balances{Sender: "1000000000001", Escrow: "999999999999", Recipient: "5"},
			wantErr: "balance deltas",
		},
		{
			name:    "bad refund",
			before:  state.Balances{Sender: "1000000000000", Escrow: "0", Recipient: "4"},
			after:   state.Balances{Sender: "0", Escrow: "1000000000000", Recipient: "4"},
			wantErr: "did not refund",
		},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			_, err := classifyPacketBalances(tc.success, "1000000000000", &tc.before, &tc.after)
			if tc.wantErr == "" && err != nil {
				t.Fatal(err)
			}
			if tc.wantErr != "" && (err == nil || !strings.Contains(err.Error(), tc.wantErr)) {
				t.Fatalf("error = %v", err)
			}
		})
	}
}

func TestAmountBoundaryBalanceClassification(t *testing.T) {
	max := state.Balances{
		Sender: maxLedgerAmount, Escrow: "0", Recipient: "0",
	}
	afterMax := state.Balances{
		Sender: "0", Escrow: maxLedgerAmount, Recipient: maxLedgerAmount,
	}
	if _, err := classifyBoundaryBalances(true, maxLedgerAmount, max, afterMax); err != nil {
		t.Fatal(err)
	}
	refunded := state.Balances{
		Sender: overflowLedgerAmount, Escrow: "0", Recipient: "0",
	}
	if _, err := classifyBoundaryBalances(
		false, overflowLedgerAmount, refunded, refunded,
	); err != nil {
		t.Fatal(err)
	}
	if _, err := classifyBoundaryBalances(
		false, overflowLedgerAmount, refunded,
		state.Balances{Sender: "0", Escrow: overflowLedgerAmount, Recipient: "0"},
	); err == nil {
		t.Fatal("unrefunded overflow unexpectedly passed")
	}
}

func TestPacketSubmittingPhasesNeverRepeatWrites(t *testing.T) {
	for _, phase := range []state.Phase{
		state.PhasePacketMintSubmitting,
		state.PhasePacketApproveSubmitting,
		state.PhasePacketSendSubmitting,
	} {
		t.Run(string(phase), func(t *testing.T) {
			cfg := testConfig(t)
			recorder := new(recordingExecutor)
			runner := &Runner{
				cfg: cfg, current: state.State{
					Phase: phase, Packet: &state.Packet{Phase: phase},
				},
				evm: evm.NewWithExecutor(cfg, recorder), gno: gno.NewWithExecutor(cfg, recorder),
			}
			err := runner.runERC20ToGnoScenario(context.Background())
			if err == nil || !strings.Contains(err.Error(), "submission is ambiguous") {
				t.Fatalf("error = %v", err)
			}
			if len(recorder.commands) != 0 {
				t.Fatalf("submitting resume issued commands: %#v", recorder.commands)
			}
		})
	}
}

func TestPacketCheckpointFailurePreventsMint(t *testing.T) {
	cfg := testConfig(t)
	cfg.EVMPrivateKey = "0x" + strings.Repeat("c", 64)
	cfg.EVMPacketRPCURL = "https://evm.example"
	cfg.StateFile = filepath.Join(t.TempDir(), "missing", "state.json")
	recorder := &recordingExecutor{results: []process.Result{
		{Stdout: []byte("0x7777777777777777777777777777777777777777")},
		{Stdout: []byte("0x01")},
		{Stdout: []byte("18")},
		{Stdout: []byte("0x01")},
		{Stdout: []byte("0x02")},
		{Stdout: []byte("0x" + strings.Repeat("a", 64))},
		{Stdout: []byte("0x03")},
		{Stdout: []byte("0x" + strings.Repeat("b", 64))},
	}}
	runner := &Runner{
		cfg: cfg, current: completedState(cfg, 7),
		evm: evm.NewWithExecutor(cfg, recorder), gno: gno.NewWithExecutor(cfg, recorder),
	}
	if err := runner.runERC20ToGnoScenario(context.Background()); err == nil {
		t.Fatal("packet checkpoint failure unexpectedly passed")
	}
	for _, command := range recorder.commands {
		if command.Name == "cast" && len(command.Args) != 0 && command.Args[0] == "send" {
			t.Fatalf("checkpoint failure issued mint: %#v", command)
		}
	}
}

func TestFailureOutcomeWritesEvidenceBeforeReturning(t *testing.T) {
	cfg := testConfig(t)
	if err := state.PrepareArtifacts(
		filepath.Dir(filepath.Dir(cfg.ScriptDir)), cfg.ScriptDir, cfg.ArtifactDir, cfg.StateFile,
	); err != nil {
		t.Fatal(err)
	}
	runner := &Runner{cfg: cfg, current: completedState(cfg, 7)}
	runner.current.Phase = state.PhasePacketSendSubmitted
	runner.current.Packet = validPacket(cfg, 7, state.PhasePacketSendSubmitted, "")
	gnoTx := base64.StdEncoding.EncodeToString(make([]byte, 32))
	err := runner.finishPacket(packetResult{
		GnoReceiveTx: gnoTx, GnoWriteAckTx: gnoTx,
		EVMAckTx:    "0x" + strings.Repeat("e", 64),
		Outcome:     state.PacketOutcomeFailure,
		Deltas:      state.Balances{Sender: "0", Escrow: "0", Recipient: "0"},
		FailedFinal: 7,
	})
	if err == nil || !strings.Contains(err.Error(), "refund verified") {
		t.Fatalf("error = %v", err)
	}
	saved, err := state.Load(cfg.StateFile)
	if err != nil {
		t.Fatal(err)
	}
	if err := saved.Validate(expectedState(cfg)); err != nil {
		t.Fatal(err)
	}
	evidence, err := os.ReadFile(filepath.Join(cfg.ArtifactDir, "packet-summary.json"))
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Contains(evidence, []byte(`"outcome": "failure"`)) ||
		!bytes.Contains(evidence, []byte(`"gno_write_ack"`)) {
		t.Fatalf("failure evidence is incomplete: %s", evidence)
	}
}

func TestFailureAcknowledgementVerifiesRefundBeforeReturning(t *testing.T) {
	cfg := testConfig(t)
	cfg.CommandTimeout = time.Second
	cfg.ScenarioTimeout = time.Second
	cfg.PollInterval = 0
	cfg.VoyagerStopTimeout = time.Second
	if err := state.PrepareArtifacts(
		filepath.Dir(filepath.Dir(cfg.ScriptDir)), cfg.ScriptDir, cfg.ArtifactDir, cfg.StateFile,
	); err != nil {
		t.Fatal(err)
	}
	packetHash := "0x" + strings.Repeat("d", 64)
	ack := encodedAcknowledgement(0, []byte("refund"))
	gnoTx := base64.StdEncoding.EncodeToString(make([]byte, 32))
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		attrs := fmt.Sprintf(
			`[{"key":"packet_hash","value":%q},{"key":"acknowledgement","value":%q}]`,
			packetHash, ack,
		)
		fmt.Fprintf(w, `{"data":{"getTransactions":[{"hash":%q,"response":{"events":[`+
			`{"type":"PacketRecv","pkg_path":%q,"attrs":[{"key":"packet_hash","value":%q}]},`+
			`{"type":"WriteAck","pkg_path":%q,"attrs":%s}]}}]}}`,
			gnoTx, cfg.GnoIBCCoreRealm, packetHash, cfg.GnoIBCCoreRealm, attrs)
	}))
	defer server.Close()
	cfg.GnoPacketIndexerRPCURL = server.URL
	cfg.GnoPacketRPCURL = "https://gno.example"
	cfg.GnoIBCCoreRealm = "gno.land/r/onbloc/ibc/union/core"
	cfg.EVMPacketRPCURL = "https://evm.example"
	executor := &packetFailureExecutor{ack: ack, packetHash: packetHash}
	runtime := voyager.NewWithExecutor(cfg, executor, io.Discard)
	if err := runtime.Start(context.Background(), []byte("{}")); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		if err := runtime.Close(context.Background()); err != nil {
			t.Error(err)
		}
	})
	current := completedState(cfg, 7)
	current.Phase = state.PhasePacketSendSubmitted
	current.Packet = validPacket(cfg, 7, state.PhasePacketSendSubmitted, "")
	runner := &Runner{
		cfg: cfg, voyager: runtime,
		evm: evm.NewWithExecutor(cfg, executor), gno: gno.NewWithExecutor(cfg, executor), current: current,
	}
	err := runner.runERC20ToGnoScenario(context.Background())
	if err == nil || !strings.Contains(err.Error(), "refund verified") {
		t.Fatalf("error = %v", err)
	}
	saved, err := state.Load(cfg.StateFile)
	if err != nil {
		t.Fatal(err)
	}
	if saved.Packet.Outcome != state.PacketOutcomeFailure ||
		*saved.Packet.BalanceDeltas !=
			(state.Balances{Sender: "0", Escrow: "0", Recipient: "0"}) ||
		!saved.Packet.CommitmentCleared {
		t.Fatalf("saved failure result = %#v", saved.Packet)
	}
	for _, command := range executor.commands {
		if command.Name == "cast" && len(command.Args) != 0 && command.Args[0] == "send" {
			t.Fatalf("failure verification issued write: %#v", command)
		}
	}
}

func TestCompletedPacketResumePerformsNoPacketWrites(t *testing.T) {
	tests := []struct {
		name    string
		outcome state.PacketOutcome
		legacy  bool
	}{
		{"success", state.PacketOutcomeSuccess, false},
		{"failure", state.PacketOutcomeFailure, false},
		{"fixed-point success", state.PacketOutcomeSuccess, true},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			cfg := resumableState(t, state.PhaseComplete)
			saved, err := state.Load(cfg.StateFile)
			if err != nil {
				t.Fatal(err)
			}
			final := int64(7)
			saved.FailedWork.Final = &final
			saved.Phase = state.PhasePacketComplete
			saved.Packet = validPacket(cfg, 7, state.PhasePacketComplete, tc.outcome)
			if tc.legacy {
				legacyFinal := int64(0)
				saved.FailedWork.Baseline = 0
				saved.FailedWork.Final = &legacyFinal
				saved.FailedWork.Repaired = []int64{1, 7}
				saved.Packet.Outcome = ""
				saved.Packet.CommitmentCleared = false
				saved.Packet.GnoWriteAckTx = ""
			}
			if err := state.Save(cfg.StateFile, saved); err != nil {
				t.Fatal(err)
			}
			binDir := t.TempDir()
			for _, name := range []string{"cast", "gnokey"} {
				if err := os.WriteFile(
					filepath.Join(binDir, name), []byte("#!/bin/sh\n"), 0o700,
				); err != nil {
					t.Fatal(err)
				}
			}
			t.Setenv("PATH", binDir)
			recorder := new(resumeExecutor)
			runner, err := newRunner(
				cfg, recorder, Options{Apply: true, Resume: true, ERC20ToGno: true},
			)
			if err != nil {
				t.Fatal(err)
			}
			runErr := runner.Run(context.Background())
			if tc.outcome == state.PacketOutcomeSuccess && runErr != nil {
				t.Fatal(runErr)
			}
			if tc.outcome == state.PacketOutcomeFailure &&
				(runErr == nil || !strings.Contains(runErr.Error(), "refund verified")) {
				t.Fatalf("failure resume error = %v", runErr)
			}
			if recorder.broadcasts != 0 {
				t.Fatalf("broadcasts = %d, want zero", recorder.broadcasts)
			}
			for _, command := range recorder.commands {
				if !readOnlyResumeCommand(command) {
					t.Fatalf("completed packet resume issued write: %s %s",
						command.Name, strings.Join(command.Args, " "))
				}
			}
		})
	}
}

type packetFailureExecutor struct {
	resumeExecutor
	ack, packetHash string
}

func (e *packetFailureExecutor) Run(
	ctx context.Context,
	command process.Command,
) (process.Result, error) {
	if command.Name != "cast" && command.Name != "gnokey" {
		return e.resumeExecutor.Run(ctx, command)
	}
	e.commands = append(e.commands, command)
	if command.Name == "gnokey" {
		return process.Result{Stdout: []byte("(0 int64)")}, nil
	}
	switch {
	case command.Args[0] == "rpc":
		channel := "0x" + strings.Repeat("0", 62) + "16"
		logs := fmt.Sprintf(
			`[{"address":%q,"topics":[%q,%q,%q],"data":"0x01","transactionHash":%q}]`,
			"0x1111111111111111111111111111111111111111",
			packetAckTopicForTest, channel, e.packetHash, "0x"+strings.Repeat("e", 64),
		)
		return process.Result{Stdout: []byte(logs)}, nil
	case command.Args[0] == "decode-abi":
		return process.Result{Stdout: []byte(fmt.Sprintf("[%q]", e.ack))}, nil
	case command.Args[0] == "abi-encode":
		return process.Result{Stdout: []byte("0x01")}, nil
	case command.Args[0] == "keccak":
		return process.Result{Stdout: []byte("0x" + strings.Repeat("f", 64))}, nil
	case command.Args[0] == "call" && strings.Contains(strings.Join(command.Args, " "), "commitments"):
		return process.Result{Stdout: []byte("0x02" + strings.Repeat("0", 62))}, nil
	case command.Args[0] == "call" && command.Args[len(command.Args)-1] ==
		"0x7777777777777777777777777777777777777777":
		return process.Result{Stdout: []byte("2000000000000")}, nil
	case command.Args[0] == "call":
		return process.Result{Stdout: []byte("0")}, nil
	default:
		return process.Result{}, fmt.Errorf("unexpected packet command")
	}
}

const packetAckTopicForTest = "0x41d958a7d93b50b1f7541c6fc345d0c" +
	"4657b1e83497baa562c866611ac1f69bb"

func validPacket(
	cfg config.Config,
	baseline int64,
	phase state.Phase,
	outcome state.PacketOutcome,
) *state.Packet {
	block := uint64(10)
	final := baseline
	gnoTx := base64.StdEncoding.EncodeToString(make([]byte, 32))
	packet := &state.Packet{
		Phase: phase,
		Token: cfg.EVMTestERC20, Sender: "0x7777777777777777777777777777777777777777",
		Recipient: cfg.GnoRecipient, Amount: cfg.EVMTestAmount,
		Voucher: "ibc/" + strings.Repeat("8", 40),
		Salt:    "0x" + strings.Repeat("9", 64), Tag: strings.Repeat("9", 64),
		FailedWorkBaseline: baseline,
		MintTx:             "0x" + strings.Repeat("a", 64),
		ApproveTx:          "0x" + strings.Repeat("b", 64),
		BalancesBefore: &state.Balances{
			Sender: "2000000000000", Escrow: "0", Recipient: "0",
		},
		EVMFromBlock: &block, SendTx: "0x" + strings.Repeat("c", 64),
		PacketHash: "0x" + strings.Repeat("d", 64),
	}
	if phase == state.PhasePacketComplete {
		packet.GnoReceiveTx, packet.GnoWriteAckTx = gnoTx, gnoTx
		packet.EVMAckTx = "0x" + strings.Repeat("e", 64)
		packet.Outcome, packet.CommitmentCleared = outcome, true
		packet.BalanceDeltas = &state.Balances{
			Sender: cfg.EVMTestAmount, Escrow: cfg.EVMTestAmount, Recipient: "1",
		}
		if outcome == state.PacketOutcomeFailure {
			packet.BalanceDeltas = &state.Balances{Sender: "0", Escrow: "0", Recipient: "0"}
		}
		packet.FailedWorkFinal = &final
	}
	return packet
}
