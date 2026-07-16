package unione2e

import (
	"strings"
	"testing"
)

func TestClientStatesFromCreate(t *testing.T) {
	client, consensus, err := clientStatesFromCreate([]byte(`{"@value":{"datagrams":[{"datagram":{"@value":{"client_state_bytes":"client","consensus_state_bytes":"consensus"}}}]}}`))
	if err != nil || client != "client" || consensus != "consensus" {
		t.Fatalf("got client=%q consensus=%q err=%v", client, consensus, err)
	}
}

func TestOnlyStaleClientFailures(t *testing.T) {
	if !onlyStaleClientFailures("1 10-gno: new val set cannot be trusted\n2 10-gno: new val set cannot be trusted") {
		t.Fatal("stale-only rows rejected")
	}
	if onlyStaleClientFailures("1 10-gno: new val set cannot be trusted\n2 unrelated") {
		t.Fatal("unrelated failure accepted")
	}
}

func TestCheckCosmosTxResponse(t *testing.T) {
	if err := checkCosmosTxResponse([]byte(`{"code":0,"txhash":"ok"}`)); err != nil {
		t.Fatalf("successful transaction rejected: %v", err)
	}
	err := checkCosmosTxResponse([]byte(`{"code":7,"raw_log":"unauthorized"}`))
	if err == nil || !strings.Contains(err.Error(), "code 7: unauthorized") {
		t.Fatalf("failed transaction error = %v", err)
	}
}

func TestCosmosTxHash(t *testing.T) {
	hash, err := cosmosTxHash([]byte(`{"code":0,"txhash":"ABC123"}`))
	if err != nil || hash != "ABC123" {
		t.Fatalf("hash=%q err=%v", hash, err)
	}
	if _, err := cosmosTxHash([]byte(`{"code":0}`)); err == nil {
		t.Fatal("missing txhash accepted")
	}
}

func TestCheckUnionEventOrder(t *testing.T) {
	ordered := []byte(`{"events":[{"type":"wasm-packet_recv"},{"type":"wasm-write_ack"}]}`)
	if err := checkUnionEventOrder(ordered, "wasm-packet_recv", "wasm-write_ack"); err != nil {
		t.Fatalf("ordered events rejected: %v", err)
	}

	reversed := []byte(`{"events":[{"type":"wasm-write_ack"},{"type":"wasm-packet_recv"}]}`)
	err := checkUnionEventOrder(reversed, "wasm-packet_recv", "wasm-write_ack")
	if err == nil || !strings.Contains(err.Error(), "must precede") {
		t.Fatalf("reversed event error = %v", err)
	}
}
