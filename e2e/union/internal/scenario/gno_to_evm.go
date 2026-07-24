package scenario

import (
	"bytes"
	"context"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strconv"
	"strings"

	"github.com/onbloc/gno-ibc/e2e/union/internal/evm"
	"github.com/onbloc/gno-ibc/e2e/union/internal/state"
)

const (
	nativeLifecycleAmount   = "1"
	nativeLifecycleReceiver = "g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm"
)

type gnoOrderResult struct {
	Name             string `json:"name"`
	PacketHash       string `json:"packet_hash"`
	SourceTx         string `json:"source_tx"`
	DestinationTx    string `json:"destination_tx"`
	AckTx            string `json:"ack_tx"`
	Success          bool   `json:"success"`
	WireSender       string `json:"wire_sender,omitempty"`
	ProofClient      int64  `json:"proof_client,omitempty"`
	ProofHeight      string `json:"proof_height,omitempty"`
	MembershipClient int64  `json:"membership_client,omitempty"`
	MembershipHeight int64  `json:"membership_height,omitempty"`
	MembershipPath   string `json:"membership_path,omitempty"`
}

func (r *Runner) runGnoToEVMScenarios(ctx context.Context) error {
	if r.current.Phase != state.PhasePacketComplete ||
		r.current.Packet.Outcome != state.PacketOutcomeSuccess {
		return fmt.Errorf("Gno-to-EVM scenarios require a successful ERC20 packet")
	}
	from, err := r.voyager.LatestFinalizedHeight(ctx, r.cfg.EVMChainID)
	if err != nil {
		return err
	}
	if err := r.voyager.Index(ctx, r.cfg.EVMChainID, from); err != nil {
		return err
	}
	lifecycle, err := r.runTokenLifecycle(ctx)
	if err != nil {
		return err
	}
	invalid, err := r.runInvalidQuote(ctx)
	if err != nil {
		return err
	}
	return r.writeEvidence("gno-to-evm.json", map[string]any{
		"lifecycle": lifecycle, "invalid_quote": invalid,
	})
}

func (r *Runner) runTokenLifecycle(ctx context.Context) ([]gnoOrderResult, error) {
	plan, err := r.evm.PrepareWrappedToken(ctx, r.current.Channels.EVM, "ugnot")
	if err != nil {
		return nil, err
	}
	proxy, err := r.gno.ProxyAddress(ctx)
	if err != nil {
		return nil, err
	}
	proxyBefore, err := r.gno.NativeBalance(ctx, proxy, "ugnot")
	if err != nil {
		return nil, err
	}
	fromBlock, err := r.evm.BlockNumber(ctx)
	if err != nil {
		return nil, err
	}
	initialize, err := r.runGnoOrder(
		ctx, "initialize", r.cfg.GnoRecipient, plan, 0, true,
	)
	if err != nil {
		return nil, err
	}
	escrow, err := r.runGnoOrder(
		ctx, "escrow", r.cfg.GnoRecipient, plan, 1, true,
	)
	if err != nil {
		return nil, err
	}
	if err := r.requireWrappedState(ctx, plan, fromBlock, "2", 1); err != nil {
		return nil, err
	}
	proxyAfterEscrow, err := r.gno.NativeBalance(ctx, proxy, "ugnot")
	if err != nil {
		return nil, err
	}
	if proxyAfterEscrow-proxyBefore != 2 {
		return nil, fmt.Errorf("Gno proxy did not escrow both lifecycle sends")
	}

	if _, err := r.evm.ApproveToken(ctx, plan.Token, nativeLifecycleAmount); err != nil {
		return nil, err
	}
	receiverBefore, err := r.gno.NativeBalance(ctx, nativeLifecycleReceiver, "ugnot")
	if err != nil {
		return nil, err
	}
	snapshot, err := r.evm.SnapshotToken(ctx, plan.Token, plan.Sender)
	if err != nil {
		return nil, err
	}
	returnPlan, err := (evm.Plan{
		Token: plan.Token, Sender: plan.Sender, Voucher: "ugnot", Metadata: "0x",
	}).WithFreshSalt()
	if err != nil {
		return nil, err
	}
	send, err := r.evm.SendTokenOrder(
		ctx, r.current.Channels.EVM, returnPlan, nativeLifecycleReceiver,
		nativeLifecycleAmount, 2,
	)
	if err != nil {
		return nil, err
	}
	gnoReceive, err := r.gno.WaitPacket(ctx, send.PacketHash)
	if err != nil {
		return nil, err
	}
	evmAck, err := r.evm.WaitAcknowledgement(
		ctx, snapshot.Block, r.current.Channels.EVM, send.PacketHash,
	)
	if err != nil {
		return nil, err
	}
	success, err := matchingAcknowledgementResult(
		gnoReceive.Acknowledgement, evmAck.Value,
	)
	if err != nil || !success {
		return nil, fmt.Errorf("UNESCROW did not receive a success acknowledgement")
	}
	if err := r.evm.VerifyCommitmentCleared(ctx, send.PacketHash); err != nil {
		return nil, err
	}
	if err := r.verifyNoNewFailedWork(ctx); err != nil {
		return nil, err
	}
	if err := r.requireWrappedState(ctx, plan, fromBlock, "1", 1); err != nil {
		return nil, err
	}
	receiverAfter, err := r.gno.NativeBalance(ctx, nativeLifecycleReceiver, "ugnot")
	if err != nil {
		return nil, err
	}
	proxyAfter, err := r.gno.NativeBalance(ctx, proxy, "ugnot")
	if err != nil {
		return nil, err
	}
	if receiverAfter-receiverBefore != 1 || proxyAfter-proxyBefore != 1 {
		return nil, fmt.Errorf(
			"UNESCROW balance deltas receiver=%d proxy=%d, want 1 each",
			receiverAfter-receiverBefore, proxyAfter-proxyBefore,
		)
	}
	unescrow := gnoOrderResult{
		Name: "unescrow", PacketHash: send.PacketHash, SourceTx: send.Tx,
		DestinationTx: gnoReceive.ReceiveTx, AckTx: evmAck.Tx, Success: true,
	}
	return []gnoOrderResult{initialize, escrow, unescrow}, nil
}

func (r *Runner) runInvalidQuote(ctx context.Context) (gnoOrderResult, error) {
	plan, err := r.evm.PrepareWrappedToken(ctx, r.current.Channels.EVM+1, "ugnot")
	if err != nil {
		return gnoOrderResult{}, err
	}
	proxy, err := r.gno.ProxyAddress(ctx)
	if err != nil {
		return gnoOrderResult{}, err
	}
	before, err := r.gno.NativeBalance(ctx, proxy, "ugnot")
	if err != nil {
		return gnoOrderResult{}, err
	}
	recipientBefore, err := r.gno.NativeBalance(ctx, nativeLifecycleReceiver, "ugnot")
	if err != nil {
		return gnoOrderResult{}, err
	}
	result, err := r.runGnoOrder(
		ctx, "invalid-quote-refund", nativeLifecycleReceiver, plan, 0, false,
	)
	if err != nil {
		return gnoOrderResult{}, err
	}
	after, err := r.gno.NativeBalance(ctx, proxy, "ugnot")
	if err != nil {
		return gnoOrderResult{}, err
	}
	recipientAfter, err := r.gno.NativeBalance(ctx, nativeLifecycleReceiver, "ugnot")
	if err != nil {
		return gnoOrderResult{}, err
	}
	if after != before || recipientAfter-recipientBefore != 1 {
		return gnoOrderResult{}, fmt.Errorf("invalid quote packet was not fully refunded")
	}
	count, err := r.gno.EventCount(ctx, "PacketTimeout", result.PacketHash)
	if err != nil {
		return gnoOrderResult{}, err
	}
	if count != 0 {
		return gnoOrderResult{}, fmt.Errorf("invalid quote packet unexpectedly timed out")
	}
	return result, nil
}

func (r *Runner) runGnoOrder(
	ctx context.Context,
	name string,
	sender string,
	plan evm.WrappedPlan,
	kind uint8,
	wantSuccess bool,
) (gnoOrderResult, error) {
	block, err := r.evm.BlockNumber(ctx)
	if err != nil {
		return gnoOrderResult{}, err
	}
	operand, err := r.evm.EncodeTokenOrder(
		ctx, evm.TokenOrder{
			Sender: hexText(sender), Receiver: plan.Sender,
			BaseToken: hexText("ugnot"), Amount: nativeLifecycleAmount,
			QuoteToken: plan.Token, Kind: kind, Metadata: plan.Metadata,
		},
	)
	if err != nil {
		return gnoOrderResult{}, err
	}
	expectedDelta := "0"
	if wantSuccess {
		expectedDelta = nativeLifecycleAmount
	}
	if err := r.writeEvidence("gno-"+name+"-intent.json", map[string]any{
		"operand": operand,
		"expected": map[string]string{
			"gno_proxy_delta": expectedDelta, "evm_recipient_delta": expectedDelta,
		},
	}); err != nil {
		return gnoOrderResult{}, err
	}
	send, err := r.gno.SendRaw(
		ctx, r.current.Channels.Gno, operand, nativeLifecycleAmount+"ugnot",
	)
	if err != nil {
		return gnoOrderResult{}, err
	}
	receive, err := r.evm.WaitReceive(
		ctx, block, r.current.Channels.EVM, send.PacketHash,
	)
	if err != nil {
		return gnoOrderResult{}, err
	}
	membershipPath, err := r.evm.PacketCommitmentPath(ctx, send.PacketHash)
	if err != nil {
		return gnoOrderResult{}, err
	}
	membershipHeight, err := r.unionMembershipHeight(
		ctx, r.current.Clients.UnionGno, send.Height+1, membershipPath,
	)
	if err != nil {
		return gnoOrderResult{}, err
	}
	proofHeight, err := r.voyager.ClientHeight(
		ctx, r.cfg.EVMChainID, r.current.Clients.EVMGno,
	)
	if err != nil {
		return gnoOrderResult{}, err
	}
	height, err := strconv.ParseInt(
		proofHeight[strings.LastIndex(proofHeight, "-")+1:], 10, 64,
	)
	if err != nil || height < membershipHeight {
		return gnoOrderResult{}, fmt.Errorf(
			"EVM Proof Lens height %q does not cover Union membership height %d",
			proofHeight, membershipHeight,
		)
	}
	ack, err := r.gno.WaitAcknowledgement(ctx, send.PacketHash)
	if err != nil {
		return gnoOrderResult{}, err
	}
	success, err := matchingAcknowledgementResult(
		ack.Value, receive.Acknowledgement,
	)
	if err != nil {
		return gnoOrderResult{}, err
	}
	if success != wantSuccess {
		return gnoOrderResult{}, fmt.Errorf(
			"%s acknowledgement success=%t, want %t", name, success, wantSuccess,
		)
	}
	if err := r.gno.VerifyCommitmentCleared(ctx, send.PacketHash); err != nil {
		return gnoOrderResult{}, err
	}
	if err := r.verifyNoNewFailedWork(ctx); err != nil {
		return gnoOrderResult{}, err
	}
	return gnoOrderResult{
		Name: name, PacketHash: send.PacketHash, SourceTx: send.Tx,
		DestinationTx: receive.Tx, AckTx: ack.Tx, Success: success,
		WireSender:  sender,
		ProofClient: r.current.Clients.EVMGno, ProofHeight: proofHeight,
		MembershipClient: r.current.Clients.UnionGno,
		MembershipHeight: membershipHeight,
		MembershipPath:   strings.TrimPrefix(membershipPath, "0x"),
	}, nil
}

func (r *Runner) unionMembershipHeight(
	ctx context.Context,
	clientID, minimum int64,
	path string,
) (int64, error) {
	query := fmt.Sprintf(
		"wasm-commit_membership_proof.client_id='%d'", clientID,
	)
	body, _ := json.Marshal(map[string]any{
		"jsonrpc": "2.0", "id": 1, "method": "tx_search",
		"params": map[string]any{
			"query": query, "prove": false, "page": "1",
			"per_page": "100", "order_by": "desc",
		},
	})
	request, err := http.NewRequestWithContext(
		ctx, http.MethodPost, r.cfg.UnionPacketRPCURL, bytes.NewReader(body),
	)
	if err != nil {
		return 0, err
	}
	request.Header.Set("Content-Type", "application/json")
	client := http.Client{Timeout: r.cfg.CommandTimeout}
	response, err := client.Do(request)
	if err != nil {
		return 0, err
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return 0, fmt.Errorf("Union tx search returned %s", response.Status)
	}
	var result struct {
		Error  json.RawMessage `json:"error"`
		Result struct {
			Txs []struct {
				TxResult struct {
					Events []struct {
						Type       string `json:"type"`
						Attributes []struct {
							Key, Value string
						} `json:"attributes"`
					} `json:"events"`
				} `json:"tx_result"`
			} `json:"txs"`
		} `json:"result"`
	}
	if err := json.NewDecoder(io.LimitReader(response.Body, 2<<20)).Decode(&result); err != nil ||
		len(result.Error) != 0 && string(result.Error) != "null" {
		return 0, fmt.Errorf("malformed Union tx search response")
	}
	path = strings.TrimPrefix(strings.ToLower(path), "0x")
	var matches []int64
	for _, tx := range result.Result.Txs {
		for _, event := range tx.TxResult.Events {
			if event.Type != "wasm-commit_membership_proof" &&
				event.Type != "commit_membership_proof" {
				continue
			}
			attributes := make(map[string]string, len(event.Attributes))
			for _, attribute := range event.Attributes {
				attributes[attribute.Key] = attribute.Value
			}
			height, err := strconv.ParseInt(attributes["proof_height"], 10, 64)
			if err == nil &&
				attributes["client_id"] == strconv.FormatInt(clientID, 10) &&
				height >= minimum &&
				strings.TrimPrefix(strings.ToLower(attributes["path"]), "0x") == path {
				matches = append(matches, height)
			}
		}
	}
	if len(matches) != 1 {
		return 0, fmt.Errorf(
			"Union membership proof count=%d for client=%d path=%s, want one",
			len(matches), clientID, path,
		)
	}
	return matches[0], nil
}

func (r *Runner) requireWrappedState(
	ctx context.Context,
	plan evm.WrappedPlan,
	fromBlock uint64,
	wantBalance string,
	wantCreations int,
) error {
	code, err := r.evm.CodeExists(ctx, plan.Token)
	if err != nil {
		return err
	}
	if !code {
		return fmt.Errorf("EVM wrapped token was not deployed")
	}
	balance, _, err := r.evm.TokenBalances(ctx, plan.Token, plan.Sender)
	if err != nil {
		return err
	}
	supply, err := r.evm.TotalSupply(ctx, plan.Token)
	if err != nil {
		return err
	}
	creations, err := r.evm.WrappedTokenCreatedCount(
		ctx, fromBlock, r.current.Channels.EVM, plan.Token,
	)
	if err != nil {
		return err
	}
	if balance != wantBalance || supply != wantBalance || creations != wantCreations {
		return fmt.Errorf("EVM wrapped token lifecycle state is incorrect")
	}
	return nil
}

func hexText(value string) string {
	return "0x" + hex.EncodeToString([]byte(value))
}
