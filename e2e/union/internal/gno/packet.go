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
	"strconv"
	"strings"
	"time"
)

var acknowledgementColumnPattern = regexp.MustCompile(`^acknowledgement\[([0-9]+)\]$`)

// PacketEvents identifies the matching receive and acknowledgement.
type PacketEvents struct {
	ReceiveTx, WriteAckTx, Acknowledgement string
}

type packetEvent struct {
	Type   string
	TxHash string
	Attrs  []attribute
}

type attribute struct {
	Key   string `json:"key"`
	Value string `json:"value"`
}

// WaitPacket requires exactly one PacketRecv and WriteAck in the same Gno transaction.
func (c *Client) WaitPacket(ctx context.Context, packetHash string) (PacketEvents, error) {
	waitCtx, cancel := context.WithTimeout(ctx, c.cfg.ScenarioTimeout)
	defer cancel()
	for {
		events, err := c.packetEvents(waitCtx, packetHash)
		if err != nil {
			return PacketEvents{}, err
		}
		var receive, writeAck []packetEvent
		for _, event := range events {
			switch event.Type {
			case "PacketRecv":
				receive = append(receive, event)
			case "WriteAck":
				writeAck = append(writeAck, event)
			}
		}
		if len(receive) > 1 {
			return PacketEvents{}, fmt.Errorf("Gno PacketRecv count=%d, want exactly one", len(receive))
		}
		if len(writeAck) > 1 {
			return PacketEvents{}, fmt.Errorf("Gno WriteAck count=%d, want exactly one", len(writeAck))
		}
		if len(receive) == 0 || len(writeAck) == 0 {
			if err := pause(waitCtx, c.cfg.PollInterval); err != nil {
				return PacketEvents{}, fmt.Errorf("Gno packet events were not visible: %w", err)
			}
			continue
		}
		if receive[0].TxHash != writeAck[0].TxHash {
			return PacketEvents{}, fmt.Errorf("Gno PacketRecv and WriteAck transactions differ")
		}
		acknowledgement, err := parseAcknowledgement(writeAck[0].Attrs)
		if err != nil {
			return PacketEvents{}, err
		}
		return PacketEvents{
			ReceiveTx: receive[0].TxHash, WriteAckTx: writeAck[0].TxHash,
			Acknowledgement: acknowledgement,
		}, nil
	}
}

func (c *Client) packetEvents(ctx context.Context, packetHash string) ([]packetEvent, error) {
	query := fmt.Sprintf(
		`{ getTransactions(where: { success: { eq: true } response: { events: { _or: [{ GnoEvent: { type: { eq: "PacketRecv" } pkg_path: { eq: %q } _and: [{ attrs: { key: { eq: "packet_hash" } value: { eq: %q } } }] } }, { GnoEvent: { type: { eq: "WriteAck" } pkg_path: { eq: %q } _and: [{ attrs: { key: { eq: "packet_hash" } value: { eq: %q } } }] } }] } } } order: { heightAndIndex: DESC }) { hash response { events { ... on GnoEvent { type pkg_path attrs { key value } } } } } }`,
		c.cfg.GnoIBCCoreRealm, packetHash, c.cfg.GnoIBCCoreRealm, packetHash,
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
				Hash     string `json:"hash"`
				Response struct {
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
			if (candidate.Type != "PacketRecv" && candidate.Type != "WriteAck") ||
				candidate.PkgPath != c.cfg.GnoIBCCoreRealm ||
				!hasAttribute(candidate.Attrs, "packet_hash", packetHash) {
				continue
			}
			matches = append(matches, packetEvent{
				Type: candidate.Type, TxHash: tx.Hash, Attrs: candidate.Attrs,
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

func hasAttribute(attrs []attribute, key, value string) bool {
	for _, attr := range attrs {
		if attr.Key == key && attr.Value == value {
			return true
		}
	}
	return false
}

func validHex(value string) bool {
	value = strings.TrimPrefix(value, "0x")
	if value == "" || len(value)%2 != 0 {
		return false
	}
	_, err := hex.DecodeString(value)
	return err == nil
}

func pause(ctx context.Context, interval time.Duration) error {
	if interval <= 0 {
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
			return nil
		}
	}
	timer := time.NewTimer(interval)
	defer timer.Stop()
	select {
	case <-ctx.Done():
		return ctx.Err()
	case <-timer.C:
		return nil
	}
}
