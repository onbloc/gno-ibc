// Package union owns direct Union (Tendermint) RPC queries for the runner.
package union

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strconv"
	"strings"

	"github.com/onbloc/gno-ibc/e2e/union/internal/config"
)

// Client queries the Union Tendermint RPC.
type Client struct {
	cfg config.Config
}

type event struct {
	Type       string `json:"type"`
	Attributes []struct {
		Key, Value string
	} `json:"attributes"`
}

// New returns a concrete Union client.
func New(cfg config.Config) *Client {
	return &Client{cfg: cfg}
}

// MembershipHeight returns the single Union commit-membership proof height
// for one client and path at or after the given minimum height.
func (c *Client) MembershipHeight(
	ctx context.Context,
	clientID, minimum int64,
	path string,
) (int64, error) {
	events, err := c.membershipEvents(ctx, clientID)
	if err != nil {
		return 0, err
	}
	return matchingHeight(events, clientID, minimum, path)
}

func (c *Client) membershipEvents(ctx context.Context, clientID int64) ([]event, error) {
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
		ctx, http.MethodPost, c.cfg.UnionPacketRPCURL, bytes.NewReader(body),
	)
	if err != nil {
		return nil, err
	}
	request.Header.Set("Content-Type", "application/json")
	client := http.Client{Timeout: c.cfg.CommandTimeout}
	response, err := client.Do(request)
	if err != nil {
		return nil, err
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("Union tx search returned %s", response.Status)
	}
	var result struct {
		Error  json.RawMessage `json:"error"`
		Result struct {
			Txs []struct {
				TxResult struct {
					Events []event `json:"events"`
				} `json:"tx_result"`
			} `json:"txs"`
		} `json:"result"`
	}
	if err := json.NewDecoder(io.LimitReader(response.Body, 2<<20)).Decode(&result); err != nil ||
		len(result.Error) != 0 && string(result.Error) != "null" {
		return nil, fmt.Errorf("malformed Union tx search response")
	}
	var events []event
	for _, tx := range result.Result.Txs {
		events = append(events, tx.TxResult.Events...)
	}
	return events, nil
}

func matchingHeight(events []event, clientID, minimum int64, path string) (int64, error) {
	path = strings.TrimPrefix(strings.ToLower(path), "0x")
	var matches []int64
	for _, event := range events {
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
	if len(matches) != 1 {
		return 0, fmt.Errorf(
			"Union membership proof count=%d for client=%d path=%s, want one",
			len(matches), clientID, path,
		)
	}
	return matches[0], nil
}
