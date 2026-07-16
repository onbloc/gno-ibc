package unione2e

import (
	"bytes"
	"encoding/hex"
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

type BeaconSync struct {
	HeadSlot     uint64
	SyncDistance uint64
	IsSyncing    bool
	ELOffline    bool
}

type EVMLog struct {
	Address         string   `json:"address"`
	Topics          []string `json:"topics"`
	Data            string   `json:"data"`
	BlockNumber     string   `json:"blockNumber"`
	TransactionHash string   `json:"transactionHash"`
}

type EVMReceipt struct {
	TransactionHash string   `json:"transactionHash"`
	BlockNumber     string   `json:"blockNumber"`
	Status          string   `json:"status"`
	Logs            []EVMLog `json:"logs"`
}

func queryUnionCore(container, contract string, query any, result any) error {
	msg, err := json.Marshal(query)
	if err != nil {
		return err
	}
	out, err := dockerExec(container, "uniond", "query", "wasm", "contract-state", "smart", contract, string(msg), "-o", "json")
	if err != nil {
		return fmt.Errorf("query Union core: %w\n%s", err, out)
	}
	var response struct {
		Data json.RawMessage `json:"data"`
	}
	if err := json.Unmarshal([]byte(out), &response); err != nil {
		return err
	}
	return json.Unmarshal(response.Data, result)
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
	balance, err := queryUnionBalanceBig(rest, address, denom)
	if err != nil {
		return 0, err
	}
	if !balance.IsInt64() {
		return 0, fmt.Errorf("balance %s%s exceeds int64", balance, denom)
	}
	return balance.Int64(), nil
}

func queryUnionBalanceBig(rest, address, denom string) (*big.Int, error) {
	u := fmt.Sprintf("%s/cosmos/bank/v1beta1/balances/%s/by_denom?denom=%s", rest, address, url.QueryEscape(denom))
	body, err := httpGet(u)
	if err != nil {
		return nil, err
	}
	var resp struct {
		Balance struct {
			Amount string `json:"amount"`
		} `json:"balance"`
	}
	if err := json.Unmarshal(body, &resp); err != nil {
		return nil, err
	}
	if resp.Balance.Amount == "" {
		return new(big.Int), nil
	}
	balance := new(big.Int)
	if _, ok := balance.SetString(resp.Balance.Amount, 10); !ok {
		return nil, fmt.Errorf("bad %s balance %q", denom, resp.Balance.Amount)
	}
	return balance, nil
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

func requireUnionEventOrder(container, txHash, before, after string) error {
	out, err := dockerExec(container, "uniond", "query", "tx", txHash,
		"--node", "tcp://localhost:26657",
		"-o", "json",
	)
	if err != nil {
		return fmt.Errorf("query Union tx %s: %w\n%s", txHash, err, out)
	}
	if err := checkUnionEventOrder([]byte(out), before, after); err != nil {
		return fmt.Errorf("Union tx %s: %w", txHash, err)
	}
	return nil
}

func checkUnionEventOrder(body []byte, before, after string) error {
	var resp struct {
		Events []struct {
			Type string `json:"type"`
		} `json:"events"`
	}
	if err := json.Unmarshal(body, &resp); err != nil {
		return fmt.Errorf("decode transaction events: %w", err)
	}
	beforeIndex, afterIndex := -1, -1
	for i, event := range resp.Events {
		if beforeIndex < 0 && event.Type == before {
			beforeIndex = i
		}
		if afterIndex < 0 && event.Type == after {
			afterIndex = i
		}
	}
	if beforeIndex < 0 || afterIndex < 0 {
		return fmt.Errorf("missing ordered events %q and %q", before, after)
	}
	if beforeIndex >= afterIndex {
		return fmt.Errorf("event %q at index %d must precede %q at index %d", before, beforeIndex, after, afterIndex)
	}
	return nil
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

func queryEVMCode(rpc, address string) ([]byte, error) {
	var result string
	if err := evmRPC(rpc, "eth_getCode", []any{address, "latest"}, &result); err != nil {
		return nil, err
	}
	return decodeHex(result)
}

func queryEVMReceipt(rpc, txHash string) (EVMReceipt, error) {
	var receipt EVMReceipt
	if err := evmRPC(rpc, "eth_getTransactionReceipt", []any{txHash}, &receipt); err != nil {
		return EVMReceipt{}, err
	}
	if receipt.TransactionHash == "" {
		return EVMReceipt{}, fmt.Errorf("receipt %s not found", txHash)
	}
	return receipt, nil
}

func queryEVMLogs(rpc, address string, fromBlock uint64, topics ...string) ([]EVMLog, error) {
	filter := map[string]any{
		"address":   address,
		"fromBlock": fmt.Sprintf("0x%x", fromBlock),
		"toBlock":   "latest",
		"topics":    topics,
	}
	var logs []EVMLog
	if err := evmRPC(rpc, "eth_getLogs", []any{filter}, &logs); err != nil {
		return nil, err
	}
	return logs, nil
}

func evmCall(rpc, to, data string) ([]byte, error) {
	var result string
	if err := evmRPC(rpc, "eth_call", []any{map[string]string{"to": to, "data": data}, "latest"}, &result); err != nil {
		return nil, err
	}
	return decodeHex(result)
}

func evmUint32CallData(selector string, value uint32) string {
	return selector + fmt.Sprintf("%064x", value)
}

func evmAddressCallData(selector, address string) (string, error) {
	address = strings.TrimPrefix(address, "0x")
	if len(address) != 40 {
		return "", fmt.Errorf("bad EVM address %q", address)
	}
	return selector + strings.Repeat("0", 24) + strings.ToLower(address), nil
}

func abiUint(data []byte, word int) (uint64, error) {
	value, err := abiWord(data, word)
	if err != nil {
		return 0, err
	}
	return new(big.Int).SetBytes(value).Uint64(), nil
}

func abiAddress(data []byte, word int) (string, error) {
	value, err := abiWord(data, word)
	if err != nil {
		return "", err
	}
	return "0x" + hex.EncodeToString(value[12:]), nil
}

func abiBytes(data []byte, word int) ([]byte, error) {
	offsetWord, err := abiWord(data, word)
	if err != nil {
		return nil, err
	}
	offset := int(new(big.Int).SetBytes(offsetWord).Uint64())
	if offset+32 > len(data) {
		return nil, fmt.Errorf("ABI offset %d outside %d bytes", offset, len(data))
	}
	length := int(new(big.Int).SetBytes(data[offset : offset+32]).Uint64())
	if offset+32+length > len(data) {
		return nil, fmt.Errorf("ABI length %d outside %d bytes", length, len(data))
	}
	return data[offset+32 : offset+32+length], nil
}

func abiString(data []byte, word int) (string, error) {
	value, err := abiBytes(data, word)
	return string(value), err
}

func abiWord(data []byte, word int) ([]byte, error) {
	start := word * 32
	if start+32 > len(data) {
		return nil, fmt.Errorf("ABI word %d outside %d bytes", word, len(data))
	}
	return data[start : start+32], nil
}

func decodeHex(value string) ([]byte, error) {
	value = strings.TrimPrefix(value, "0x")
	if value == "" {
		return nil, nil
	}
	return hex.DecodeString(value)
}

func queryBeaconSync(beacon string) (BeaconSync, error) {
	body, err := httpGet(beacon + "/eth/v1/node/syncing")
	if err != nil {
		return BeaconSync{}, err
	}
	var resp struct {
		Data struct {
			HeadSlot     string `json:"head_slot"`
			SyncDistance string `json:"sync_distance"`
			IsSyncing    bool   `json:"is_syncing"`
			ELOffline    bool   `json:"el_offline"`
		} `json:"data"`
	}
	if err := json.Unmarshal(body, &resp); err != nil {
		return BeaconSync{}, err
	}
	head, err := strconv.ParseUint(resp.Data.HeadSlot, 10, 64)
	if err != nil {
		return BeaconSync{}, fmt.Errorf("parse beacon head slot: %w", err)
	}
	distance, err := strconv.ParseUint(resp.Data.SyncDistance, 10, 64)
	if err != nil {
		return BeaconSync{}, fmt.Errorf("parse beacon sync distance: %w", err)
	}
	return BeaconSync{
		HeadSlot:     head,
		SyncDistance: distance,
		IsSyncing:    resp.Data.IsSyncing,
		ELOffline:    resp.Data.ELOffline,
	}, nil
}

func queryBeaconFinalizedEpoch(beacon string) (uint64, error) {
	body, err := httpGet(beacon + "/eth/v1/beacon/states/head/finality_checkpoints")
	if err != nil {
		return 0, err
	}
	var resp struct {
		Data struct {
			Finalized struct {
				Epoch string `json:"epoch"`
			} `json:"finalized"`
		} `json:"data"`
	}
	if err := json.Unmarshal(body, &resp); err != nil {
		return 0, err
	}
	epoch, err := strconv.ParseUint(resp.Data.Finalized.Epoch, 10, 64)
	if err != nil {
		return 0, fmt.Errorf("parse finalized epoch: %w", err)
	}
	return epoch, nil
}

func evmHexBig(rpc, method string, params []any) (*big.Int, error) {
	var result string
	if err := evmRPC(rpc, method, params, &result); err != nil {
		return nil, err
	}
	n := new(big.Int)
	if _, ok := n.SetString(strings.TrimPrefix(result, "0x"), 16); !ok {
		return nil, fmt.Errorf("bad hex result for %s: %q", method, result)
	}
	return n, nil
}

func evmRPC(rpc, method string, params []any, result any) error {
	req := map[string]any{"jsonrpc": "2.0", "id": 1, "method": method, "params": params}
	body, err := json.Marshal(req)
	if err != nil {
		return err
	}
	resp, err := httpClient.Post(rpc, "application/json", bytes.NewReader(body))
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	var out struct {
		Result json.RawMessage `json:"result"`
		Error  json.RawMessage `json:"error"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return err
	}
	if len(out.Error) != 0 && string(out.Error) != "null" {
		return fmt.Errorf("json-rpc %s error: %s", method, out.Error)
	}
	if len(out.Result) == 0 || string(out.Result) == "null" {
		return fmt.Errorf("json-rpc %s returned null", method)
	}
	return json.Unmarshal(out.Result, result)
}
