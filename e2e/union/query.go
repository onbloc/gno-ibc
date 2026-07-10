package unione2e

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"math/big"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"
)

var httpClient = &http.Client{Timeout: 10 * time.Second}

type StatusResponse struct {
	ChainID string
	Height  int64
}

type Client struct {
	ClientID string
}

type UnionTx struct {
	Hash   string
	Height int64
}

func httpGet(url string) ([]byte, error) {
	resp, err := httpClient.Get(url)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("HTTP %d from %s: %s", resp.StatusCode, url, string(body))
	}
	return body, nil
}

func queryUnionStatus(rpc string) (*StatusResponse, error) {
	body, err := httpGet(rpc + "/status")
	if err != nil {
		return nil, err
	}
	var resp struct {
		Result struct {
			NodeInfo struct {
				Network string `json:"network"`
			} `json:"node_info"`
			SyncInfo struct {
				LatestBlockHeight string `json:"latest_block_height"`
			} `json:"sync_info"`
		} `json:"result"`
	}
	if err := json.Unmarshal(body, &resp); err != nil {
		return nil, err
	}
	height, err := strconv.ParseInt(resp.Result.SyncInfo.LatestBlockHeight, 10, 64)
	if err != nil {
		return nil, fmt.Errorf("parse union height: %w", err)
	}
	if resp.Result.NodeInfo.Network == "" {
		return nil, fmt.Errorf("empty union chain id")
	}
	return &StatusResponse{ChainID: resp.Result.NodeInfo.Network, Height: height}, nil
}

func queryUnionBalance(rest, address, denom string) (int64, error) {
	u := fmt.Sprintf("%s/cosmos/bank/v1beta1/balances/%s/by_denom?denom=%s", rest, address, url.QueryEscape(denom))
	body, err := httpGet(u)
	if err != nil {
		return 0, err
	}
	var resp struct {
		Balance struct {
			Amount string `json:"amount"`
		} `json:"balance"`
	}
	if err := json.Unmarshal(body, &resp); err != nil {
		return 0, err
	}
	if resp.Balance.Amount == "" {
		return 0, nil
	}
	return strconv.ParseInt(resp.Balance.Amount, 10, 64)
}

func queryUnionIBCClients(rest string) ([]Client, error) {
	body, err := httpGet(rest + "/ibc/core/client/v1/client_states")
	if err != nil {
		return nil, err
	}
	var resp struct {
		ClientStates []struct {
			ClientID string `json:"client_id"`
		} `json:"client_states"`
	}
	if err := json.Unmarshal(body, &resp); err != nil {
		return nil, err
	}
	clients := make([]Client, 0, len(resp.ClientStates))
	for _, state := range resp.ClientStates {
		clients = append(clients, Client{ClientID: state.ClientID})
	}
	return clients, nil
}

func queryUnionTxs(container, eventType, packetHash string, limit int) ([]UnionTx, error) {
	out, err := dockerExec(container, "uniond", "query", "txs",
		"--query", fmt.Sprintf("%s.packet_hash='%s'", eventType, packetHash),
		"--node", "tcp://localhost:26657",
		"-o", "json",
		"--limit", strconv.Itoa(limit),
		"--order_by", "desc",
	)
	if err != nil {
		return nil, fmt.Errorf("query Union %s: %w\n%s", eventType, err, out)
	}
	var resp struct {
		Txs []struct {
			Hash   string `json:"hash"`
			Height string `json:"height"`
		} `json:"txs"`
		TxResponses []struct {
			TxHash string `json:"txhash"`
			Height string `json:"height"`
		} `json:"tx_responses"`
	}
	if err := json.Unmarshal([]byte(out), &resp); err != nil {
		return nil, err
	}
	txs := make([]UnionTx, 0, len(resp.TxResponses)+len(resp.Txs))
	for _, tx := range resp.TxResponses {
		height, err := strconv.ParseInt(tx.Height, 10, 64)
		if err != nil {
			return nil, fmt.Errorf("parse Union tx height %q: %w", tx.Height, err)
		}
		txs = append(txs, UnionTx{Hash: tx.TxHash, Height: height})
	}
	for _, tx := range resp.Txs {
		height, err := strconv.ParseInt(tx.Height, 10, 64)
		if err != nil {
			return nil, fmt.Errorf("parse Union tx height %q: %w", tx.Height, err)
		}
		txs = append(txs, UnionTx{Hash: tx.Hash, Height: height})
	}
	return txs, nil
}

func queryEVMBalance(rpc, address string) (*big.Int, error) {
	return evmHexBig(rpc, "eth_getBalance", []any{address, "latest"})
}

func queryEVMBlockNumber(rpc string) (uint64, error) {
	n, err := evmHexBig(rpc, "eth_blockNumber", []any{})
	if err != nil {
		return 0, err
	}
	return n.Uint64(), nil
}

func queryEVMChainID(rpc string) (uint64, error) {
	n, err := evmHexBig(rpc, "eth_chainId", []any{})
	if err != nil {
		return 0, err
	}
	return n.Uint64(), nil
}

func queryBeaconHead(beacon string) (string, error) {
	body, err := httpGet(beacon + "/eth/v2/beacon/blocks/head")
	if err != nil {
		return "", err
	}
	var resp struct {
		Data struct {
			Message struct {
				Slot string `json:"slot"`
			} `json:"message"`
		} `json:"data"`
	}
	if err := json.Unmarshal(body, &resp); err != nil {
		return "", err
	}
	if resp.Data.Message.Slot == "" {
		return "", fmt.Errorf("empty beacon head slot")
	}
	return resp.Data.Message.Slot, nil
}

func queryPacketCommitment(chain, port, channel, seq string) error {
	_, err := httpGet(fmt.Sprintf("%s/ibc/core/channel/v1/channels/%s/ports/%s/packet_commitments/%s", chain, channel, port, seq))
	return err
}

func queryAcknowledgement(chain, port, channel, seq string) error {
	_, err := httpGet(fmt.Sprintf("%s/ibc/core/channel/v1/channels/%s/ports/%s/packet_acknowledgements/%s", chain, channel, port, seq))
	return err
}

func evmHexBig(rpc, method string, params []any) (*big.Int, error) {
	req := map[string]any{"jsonrpc": "2.0", "id": 1, "method": method, "params": params}
	body, err := json.Marshal(req)
	if err != nil {
		return nil, err
	}
	resp, err := httpClient.Post(rpc, "application/json", bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	var out struct {
		Result string          `json:"result"`
		Error  json.RawMessage `json:"error"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return nil, err
	}
	if len(out.Error) != 0 && string(out.Error) != "null" {
		return nil, fmt.Errorf("json-rpc %s error: %s", method, out.Error)
	}
	n := new(big.Int)
	if _, ok := n.SetString(strings.TrimPrefix(out.Result, "0x"), 16); !ok {
		return nil, fmt.Errorf("bad hex result for %s: %q", method, out.Result)
	}
	return n, nil
}
