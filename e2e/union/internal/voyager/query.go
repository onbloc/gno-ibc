package voyager

import (
	"bytes"
	"context"
	"encoding/json"
	"strconv"
	"strings"
)

type clientInfo struct {
	ClientType   string `json:"client_type"`
	IBCInterface string `json:"ibc_interface"`
}

type clientMeta struct {
	CounterpartyChainID string `json:"counterparty_chain_id"`
	CounterpartyHeight  string `json:"counterparty_height"`
}

type stateResponse struct {
	State json.RawMessage `json:"state"`
}

type jsonID struct {
	value int64
	valid bool
}

func (id *jsonID) UnmarshalJSON(data []byte) error {
	value, err := strconv.ParseInt(strings.Trim(string(data), `"`), 10, 64)
	if err != nil || value < 0 {
		return ErrMalformedResponse
	}
	id.value, id.valid = value, true
	return nil
}

type lensState struct {
	L1      jsonID `json:"l1_client_id"`
	L2      jsonID `json:"l2_client_id"`
	L2Chain string `json:"l2_chain_id"`
}

type connectionState struct {
	Status             string `json:"state"`
	Client             jsonID `json:"client_id"`
	CounterpartyClient jsonID `json:"counterparty_client_id"`
	Counterparty       jsonID `json:"counterparty_connection_id"`
}

type channelState struct {
	Status       string `json:"state"`
	Connection   jsonID `json:"connection_id"`
	Counterparty jsonID `json:"counterparty_channel_id"`
	Port         string `json:"counterparty_port_id"`
	Version      string `json:"version"`
}

func (r *Runtime) clientInfo(ctx context.Context, chain string, id int64) (clientInfo, error) {
	result, err := r.call(ctx, "rpc", "client-info", chain, strconv.FormatInt(id, 10))
	if err != nil {
		output := strings.ToLower(string(result.Stdout) + string(result.Stderr))
		if strings.Contains(output, "client") && strings.Contains(output, "not found") {
			return clientInfo{}, ErrNotFound
		}
		return clientInfo{}, err
	}
	if bytes.Equal(bytes.TrimSpace(result.Stdout), []byte("null")) {
		return clientInfo{}, ErrNotFound
	}
	var info clientInfo
	if json.Unmarshal(result.Stdout, &info) != nil {
		return clientInfo{}, ErrMalformedResponse
	}
	if info.ClientType == "" || strings.Contains(strings.ToLower(info.ClientType), "client not found") {
		return clientInfo{}, ErrNotFound
	}
	if info.IBCInterface == "" {
		return clientInfo{}, ErrMalformedResponse
	}
	return info, nil
}

func (r *Runtime) clientMeta(ctx context.Context, chain string, id int64) (clientMeta, error) {
	result, err := r.call(ctx, "rpc", "client-meta", chain, strconv.FormatInt(id, 10))
	if err != nil {
		return clientMeta{}, err
	}
	if bytes.Equal(bytes.TrimSpace(result.Stdout), []byte("null")) {
		return clientMeta{}, ErrNotFound
	}
	var meta clientMeta
	if json.Unmarshal(result.Stdout, &meta) != nil ||
		meta.CounterpartyChainID == "" || meta.CounterpartyHeight == "" {
		return clientMeta{}, ErrMalformedResponse
	}
	return meta, nil
}

func (r *Runtime) lensState(ctx context.Context, chain string, id int64) (lensState, error) {
	result, err := r.call(ctx, "rpc", "client-state", chain, strconv.FormatInt(id, 10), "--decode")
	if err != nil {
		return lensState{}, err
	}
	raw, err := decodeStateResponse(result.Stdout)
	if err != nil {
		return lensState{}, err
	}
	var wrapper struct {
		Value json.RawMessage `json:"@value"`
	}
	if json.Unmarshal(raw, &wrapper) == nil && len(wrapper.Value) != 0 {
		raw = wrapper.Value
	}
	var state lensState
	if json.Unmarshal(raw, &state) != nil || !state.L1.valid || !state.L2.valid || state.L2Chain == "" {
		return lensState{}, ErrMalformedResponse
	}
	return state, nil
}

func (r *Runtime) connectionState(ctx context.Context, chain string, id int64) (connectionState, error) {
	var state connectionState
	if err := r.ibcState(ctx, chain, "connection", id, &state); err != nil {
		return connectionState{}, err
	}
	if state.Status == "" || !state.Client.valid || !state.CounterpartyClient.valid {
		return connectionState{}, ErrMalformedResponse
	}
	return state, nil
}

func (r *Runtime) channelState(ctx context.Context, chain string, id int64) (channelState, error) {
	var state channelState
	if err := r.ibcState(ctx, chain, "channel", id, &state); err != nil {
		return channelState{}, err
	}
	if state.Status == "" || !state.Connection.valid || state.Port == "" || state.Version == "" {
		return channelState{}, ErrMalformedResponse
	}
	return state, nil
}

func (r *Runtime) ibcState(ctx context.Context, chain, kind string, id int64, target any) error {
	query, err := json.Marshal(map[string]any{kind: map[string]int64{kind + "_id": id}})
	if err != nil {
		return ErrMalformedResponse
	}
	result, err := r.call(ctx, "rpc", "ibc-state", chain, string(query))
	if err != nil {
		return err
	}
	raw, err := decodeStateResponse(result.Stdout)
	if err != nil {
		return err
	}
	if json.Unmarshal(raw, target) != nil {
		return ErrMalformedResponse
	}
	return nil
}

func decodeStateResponse(data []byte) (json.RawMessage, error) {
	var response stateResponse
	if json.Unmarshal(data, &response) != nil {
		return nil, ErrMalformedResponse
	}
	raw := response.State
	if len(raw) == 0 {
		return nil, ErrMalformedResponse
	}
	if bytes.Equal(bytes.TrimSpace(raw), []byte("null")) {
		return nil, ErrNotFound
	}
	return raw, nil
}
