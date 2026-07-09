package main

import (
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"time"
)

const (
	defaultIndexer       = "http://127.0.0.1:48546/graphql/query"
	corePkgPath          = "gno.land/r/onbloc/ibc/union/core"
	packetSendEventType  = "PacketSend"
	defaultVoyagerConfig = "/config/voyager-config.gno-union.jsonc"
)

type eventAttr struct {
	Key   string `json:"key"`
	Value string `json:"value"`
}

type indexedTx struct {
	Hash        string `json:"hash"`
	BlockHeight int64  `json:"block_height"`
	Response    struct {
		Events []struct {
			Type    string      `json:"type"`
			PkgPath string      `json:"pkg_path"`
			Attrs   []eventAttr `json:"attrs"`
		} `json:"events"`
	} `json:"response"`
}

type packetSend struct {
	TxHash               string
	BlockHeight          int64
	PacketHash           string
	SourceChannelID      string
	DestinationChannelID string
	PacketData           string
	TimeoutTimestamp     string
}

func main() {
	indexer := flag.String("indexer", defaultIndexer, "Gno tx-indexer GraphQL URL")
	sourceChannel := flag.String("source-channel", "", "optional source_channel_id filter")
	destinationChannel := flag.String("destination-channel", "", "optional destination_channel_id filter")
	interval := flag.Duration("interval", time.Second, "poll interval")
	once := flag.Bool("once", false, "exit after the first newly printed PacketSend")
	queueFailed := flag.Bool("queue-failed", false, "print Voyager failed queue after each detected packet")
	voyagerContainer := flag.String("voyager-container", "union-voyager-1", "Voyager Docker container for --queue-failed")
	voyagerConfig := flag.String("voyager-config", defaultVoyagerConfig, "Voyager config path inside the container")
	flag.Parse()

	seen := map[string]bool{}
	client := &http.Client{Timeout: 10 * time.Second}
	filters := map[string]string{}
	if *sourceChannel != "" {
		filters["source_channel_id"] = *sourceChannel
	}
	if *destinationChannel != "" {
		filters["destination_channel_id"] = *destinationChannel
	}

	for {
		printed, err := poll(client, *indexer, filters, seen, *queueFailed, *voyagerContainer, *voyagerConfig)
		if err != nil {
			fmt.Fprintf(os.Stderr, "packet-watch: %v\n", err)
		}
		if *once && printed {
			return
		}
		time.Sleep(*interval)
	}
}

func poll(client *http.Client, indexer string, filters map[string]string, seen map[string]bool, queueFailed bool, voyagerContainer, voyagerConfig string) (bool, error) {
	txs, err := queryPacketSends(client, indexer, filters)
	if err != nil {
		return false, err
	}
	printed := false
	for i := len(txs) - 1; i >= 0; i-- {
		for _, packet := range packetSends(txs[i]) {
			key := packet.PacketHash
			if key == "" {
				key = fmt.Sprintf("%s/%d", packet.TxHash, packet.BlockHeight)
			}
			if seen[key] {
				continue
			}
			seen[key] = true
			printPacket(packet)
			if queueFailed {
				printQueueFailed(voyagerContainer, voyagerConfig)
			}
			printed = true
		}
	}
	return printed, nil
}

func queryPacketSends(client *http.Client, indexer string, filters map[string]string) ([]indexedTx, error) {
	var ands []string
	for _, key := range []string{"source_channel_id", "destination_channel_id"} {
		if value := filters[key]; value != "" {
			ands = append(ands, fmt.Sprintf(`{ attrs: { key: { eq: %s } value: { eq: %s } } }`, strconv.Quote(key), strconv.Quote(value)))
		}
	}
	andClause := ""
	if len(ands) != 0 {
		andClause = " _and: [" + strings.Join(ands, " ") + "]"
	}
	query := fmt.Sprintf(`{
		getTransactions(
			where: { success: { eq: true } response: { events: { GnoEvent: { type: { eq: %s } pkg_path: { eq: %s }%s } } } }
			order: { heightAndIndex: DESC }
		) {
			hash
			block_height
			response { events { ... on GnoEvent { type pkg_path attrs { key value } } } }
		}
	}`, strconv.Quote(packetSendEventType), strconv.Quote(corePkgPath), andClause)

	body, err := json.Marshal(map[string]string{"query": query})
	if err != nil {
		return nil, err
	}
	resp, err := client.Post(indexer, "application/json", bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("HTTP %d from indexer: %s", resp.StatusCode, string(respBody))
	}
	var out struct {
		Data struct {
			GetTransactions []indexedTx `json:"getTransactions"`
		} `json:"data"`
		Errors []struct {
			Message string `json:"message"`
		} `json:"errors"`
	}
	if err := json.Unmarshal(respBody, &out); err != nil {
		return nil, err
	}
	if len(out.Errors) != 0 {
		return nil, fmt.Errorf("GraphQL: %s", out.Errors[0].Message)
	}
	return out.Data.GetTransactions, nil
}

func packetSends(tx indexedTx) []packetSend {
	var packets []packetSend
	for _, ev := range tx.Response.Events {
		if ev.Type != packetSendEventType || ev.PkgPath != corePkgPath {
			continue
		}
		attrs := map[string]string{}
		for _, attr := range ev.Attrs {
			attrs[attr.Key] = attr.Value
		}
		packets = append(packets, packetSend{
			TxHash:               tx.Hash,
			BlockHeight:          tx.BlockHeight,
			PacketHash:           attrs["packet_hash"],
			SourceChannelID:      attrs["source_channel_id"],
			DestinationChannelID: attrs["destination_channel_id"],
			PacketData:           packetData(attrs),
			TimeoutTimestamp:     attrs["timeout_timestamp"],
		})
	}
	return packets
}

func packetData(attrs map[string]string) string {
	if data := attrs["packet_data"]; data != "" {
		return data
	}
	var b strings.Builder
	for i := 0; ; i++ {
		part, ok := attrs["packet_data["+strconv.Itoa(i)+"]"]
		if !ok {
			break
		}
		b.WriteString(part)
	}
	return b.String()
}

func printPacket(packet packetSend) {
	fmt.Println("PacketSend detected")
	fmt.Printf("height: %d\n", packet.BlockHeight)
	fmt.Printf("tx: %s\n", packet.TxHash)
	fmt.Printf("packet_hash: %s\n", packet.PacketHash)
	fmt.Printf("source_channel_id: %s\n", packet.SourceChannelID)
	fmt.Printf("destination_channel_id: %s\n", packet.DestinationChannelID)
	fmt.Printf("timeout_timestamp: %s\n", packet.TimeoutTimestamp)
	fmt.Printf("packet_data: %s\n", packet.PacketData)
}

func printQueueFailed(container, config string) {
	cmd := exec.Command("docker", "exec", container, "./voyager", "-c", config, "queue", "query-failed")
	out, err := cmd.CombinedOutput()
	fmt.Println("voyager queue failed:")
	if err != nil {
		fmt.Printf("error: %v\n", err)
	}
	fmt.Print(string(out))
}
