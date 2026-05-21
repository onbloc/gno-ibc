package main

import (
	"encoding/binary"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"strings"
)

type getProofResponse struct {
	Result struct {
		Address      string   `json:"address"`
		Balance      string   `json:"balance"`
		CodeHash     string   `json:"codeHash"`
		Nonce        string   `json:"nonce"`
		StorageHash  string   `json:"storageHash"`
		AccountProof []string `json:"accountProof"`
		StorageProof []struct {
			Key   string   `json:"key"`
			Value string   `json:"value"`
			Proof []string `json:"proof"`
		} `json:"storageProof"`
	} `json:"result"`
}

func main() {
	in, err := io.ReadAll(os.Stdin)
	if err != nil {
		fail("read stdin: %v", err)
	}

	var resp getProofResponse
	if err := json.Unmarshal(in, &resp); err != nil {
		fail("decode eth_getProof response: %v", err)
	}
	if len(resp.Result.StorageProof) != 1 {
		fail("expected exactly one storage proof, got %d", len(resp.Result.StorageProof))
	}
	sp := resp.Result.StorageProof[0]

	key, err := word(sp.Key)
	if err != nil {
		fail("decode storage key: %v", err)
	}
	value, err := word(sp.Value)
	if err != nil {
		fail("decode storage value: %v", err)
	}

	out := make([]byte, 0, 64)
	out = append(out, reverse32(key)...)
	out = append(out, reverse32(value)...)
	out = appendUint64LE(out, uint64(len(sp.Proof)))
	for i, nodeHex := range sp.Proof {
		node, err := hexBytes(nodeHex)
		if err != nil {
			fail("decode proof node %d: %v", i, err)
		}
		out = appendUint64LE(out, uint64(len(node)))
		out = append(out, node...)
	}

	enc := json.NewEncoder(os.Stdout)
	enc.SetIndent("", "  ")
	if err := enc.Encode(map[string]any{
		"address":          resp.Result.Address,
		"storage_hash":     resp.Result.StorageHash,
		"storage_key":      "0x" + hex.EncodeToString(key),
		"storage_value":    "0x" + hex.EncodeToString(value),
		"proof_node_count": len(sp.Proof),
		"proof_bytes_hex":  "0x" + hex.EncodeToString(out),
	}); err != nil {
		fail("encode output: %v", err)
	}
}

func word(s string) ([]byte, error) {
	b, err := hexBytes(s)
	if err != nil {
		return nil, err
	}
	if len(b) > 32 {
		return nil, fmt.Errorf("word has %d bytes", len(b))
	}
	out := make([]byte, 32)
	copy(out[32-len(b):], b)
	return out, nil
}

func hexBytes(s string) ([]byte, error) {
	s = strings.TrimPrefix(strings.TrimPrefix(s, "0x"), "0X")
	if len(s)%2 != 0 {
		s = "0" + s
	}
	return hex.DecodeString(s)
}

func appendUint64LE(out []byte, v uint64) []byte {
	var word [8]byte
	binary.LittleEndian.PutUint64(word[:], v)
	return append(out, word[:]...)
}

func reverse32(b []byte) []byte {
	out := make([]byte, 32)
	for i := 0; i < 32; i++ {
		out[i] = b[31-i]
	}
	return out
}

func fail(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "ERROR: "+format+"\n", args...)
	os.Exit(1)
}
