package gno

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"regexp"
	"slices"
	"strconv"
	"strings"
)

var acknowledgementColumnPattern = regexp.MustCompile(`^acknowledgement\[([0-9]+)\]$`)

type packetEvent struct {
	Type        string
	TxHash      string
	BlockHeight int64
	Attrs       []attribute
}

type attribute struct {
	Key   string `json:"key"`
	Value string `json:"value"`
}

// EventCount returns the number of matching core events.
func (c *Client) EventCount(ctx context.Context, eventType, packetHash string) (int, error) {
	events, err := c.queryEvents(
		ctx, []string{eventType}, map[string]string{"packet_hash": packetHash},
	)
	return len(events), err
}

func (c *Client) latestEventHeight(
	ctx context.Context,
	eventType string,
	attrs map[string]string,
) (int64, error) {
	events, err := c.queryEvents(ctx, []string{eventType}, attrs)
	if err != nil || len(events) == 0 {
		return 0, err
	}
	return events[0].BlockHeight, nil
}

func (c *Client) queryEvents(
	ctx context.Context,
	eventTypes []string,
	attrs map[string]string,
) ([]packetEvent, error) {
	var conditions []string
	for _, eventType := range eventTypes {
		var attributes []string
		for key, value := range attrs {
			attributes = append(attributes, fmt.Sprintf(
				`{ attrs: { key: { eq: %q } value: { eq: %q } } }`, key, value,
			))
		}
		conditions = append(conditions, fmt.Sprintf(
			`{ GnoEvent: { type: { eq: %q } pkg_path: { eq: %q } _and: [%s] } }`,
			eventType, c.cfg.GnoIBCCoreRealm, strings.Join(attributes, " "),
		))
	}
	query := fmt.Sprintf(
		`{ getTransactions(where: { success: { eq: true } response: { events: { _or: [%s] } } } order: { heightAndIndex: DESC }) { hash block_height response { events { ... on GnoEvent { type pkg_path attrs { key value } } } } } }`,
		strings.Join(conditions, " "),
	)
	body, _ := json.Marshal(map[string]string{"query": query})
	request, err := http.NewRequestWithContext(
		ctx, http.MethodPost, c.cfg.GnoPacketIndexerRPCURL, bytes.NewReader(body),
	)
	if err != nil {
		return nil, fmt.Errorf("packet indexer request failed")
	}
	request.Header.Set("content-type", "application/json")
	client := http.Client{Timeout: c.cfg.CommandTimeout}
	response, err := client.Do(request)
	if err != nil {
		return nil, fmt.Errorf("packet indexer request failed")
	}
	defer response.Body.Close()
	if response.StatusCode < 200 || response.StatusCode >= 300 {
		return nil, fmt.Errorf("packet indexer request failed")
	}
	data, err := io.ReadAll(io.LimitReader(response.Body, 4<<20))
	if err != nil {
		return nil, fmt.Errorf("packet indexer request failed")
	}
	var payload struct {
		Errors any `json:"errors"`
		Data   struct {
			Transactions []struct {
				Hash        string `json:"hash"`
				BlockHeight int64  `json:"block_height"`
				Response    struct {
					Events []struct {
						Type    string      `json:"type"`
						PkgPath string      `json:"pkg_path"`
						Attrs   []attribute `json:"attrs"`
					} `json:"events"`
				} `json:"response"`
			} `json:"getTransactions"`
		} `json:"data"`
	}
	if json.Unmarshal(data, &payload) != nil || payload.Errors != nil {
		return nil, fmt.Errorf("malformed Gno indexer response")
	}
	var matches []packetEvent
	for _, tx := range payload.Data.Transactions {
		if !validTxHash(tx.Hash) {
			return nil, fmt.Errorf("malformed Gno transaction hash")
		}
		for _, candidate := range tx.Response.Events {
			if candidate.PkgPath != c.cfg.GnoIBCCoreRealm ||
				!slices.Contains(eventTypes, candidate.Type) ||
				!hasAttributes(candidate.Attrs, attrs) {
				continue
			}
			matches = append(matches, packetEvent{
				Type: candidate.Type, TxHash: tx.Hash,
				BlockHeight: tx.BlockHeight, Attrs: candidate.Attrs,
			})
		}
	}
	return matches, nil
}

func parseAcknowledgement(attrs []attribute) (string, error) {
	direct := ""
	directSet := false
	size := -1
	columns := make(map[int]string)
	for _, attr := range attrs {
		switch attr.Key {
		case "acknowledgement":
			if directSet {
				return "", fmt.Errorf("malformed Gno acknowledgement")
			}
			directSet = true
			direct = attr.Value
		case "acknowledgement_size":
			if size >= 0 {
				return "", fmt.Errorf("malformed Gno acknowledgement")
			}
			var err error
			size, err = strconv.Atoi(attr.Value)
			if err != nil || size <= 0 {
				return "", fmt.Errorf("malformed Gno acknowledgement")
			}
		default:
			match := acknowledgementColumnPattern.FindStringSubmatch(attr.Key)
			if len(match) == 0 {
				continue
			}
			index, err := strconv.Atoi(match[1])
			if err != nil {
				return "", fmt.Errorf("malformed Gno acknowledgement")
			}
			if _, exists := columns[index]; exists {
				return "", fmt.Errorf("malformed Gno acknowledgement")
			}
			columns[index] = attr.Value
		}
	}
	if directSet {
		if size >= 0 || len(columns) != 0 || !validHex(direct) {
			return "", fmt.Errorf("malformed Gno acknowledgement")
		}
		return direct, nil
	}
	if size < 0 || len(columns) == 0 {
		return "", fmt.Errorf("malformed Gno acknowledgement")
	}
	var acknowledgement strings.Builder
	for index := range len(columns) {
		value, exists := columns[index]
		if !exists {
			return "", fmt.Errorf("malformed Gno acknowledgement")
		}
		acknowledgement.WriteString(value)
	}
	if acknowledgement.Len() != size || !validHex(acknowledgement.String()) {
		return "", fmt.Errorf("malformed Gno acknowledgement")
	}
	return acknowledgement.String(), nil
}

func validTxHash(value string) bool {
	decoded, err := base64.StdEncoding.DecodeString(value)
	return err == nil && len(decoded) == 32
}

func hasAttributes(attrs []attribute, expected map[string]string) bool {
	for key, value := range expected {
		if attributeValue(attrs, key) != value {
			return false
		}
	}
	return true
}

func attributeValue(attrs []attribute, key string) string {
	for _, attr := range attrs {
		if attr.Key == key {
			return attr.Value
		}
	}
	return ""
}

func validHex(value string) bool {
	value = strings.TrimPrefix(value, "0x")
	if value == "" || len(value)%2 != 0 {
		return false
	}
	_, err := hex.DecodeString(value)
	return err == nil
}
