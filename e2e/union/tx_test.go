package unione2e

import "testing"

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
