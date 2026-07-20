package unione2e

import (
	"errors"
	"io"
	"net/http"
	"strings"
	"testing"
)

func TestRetrySequenceMismatch(t *testing.T) {
	attempts := 0
	out, err := retrySequenceMismatch(func() (string, error) {
		attempts++
		if attempts == 1 {
			return "account sequence mismatch", errors.New("broadcast failed")
		}
		return "ok", nil
	})
	if err != nil || out != "ok" || attempts != 2 {
		t.Fatalf("out=%q err=%v attempts=%d", out, err, attempts)
	}
}

type roundTripFunc func(*http.Request) (*http.Response, error)

func (fn roundTripFunc) RoundTrip(req *http.Request) (*http.Response, error) {
	return fn(req)
}

func TestQueryUnionBalanceBig(t *testing.T) {
	originalClient := httpClient
	httpClient = &http.Client{Transport: roundTripFunc(func(*http.Request) (*http.Response, error) {
		return &http.Response{
			StatusCode: http.StatusOK,
			Body:       io.NopCloser(strings.NewReader(`{"balance":{"amount":"9999999999999999999999999"}}`)),
		}, nil
	})}
	defer func() { httpClient = originalClient }()

	balance, err := queryUnionBalanceBig("http://union-rest", "union1sender", "au")
	if err != nil {
		t.Fatal(err)
	}
	if got, want := balance.String(), "9999999999999999999999999"; got != want {
		t.Fatalf("balance=%s want=%s", got, want)
	}
}

func TestClientStatesFromCreate(t *testing.T) {
	body := []byte("\x1b[34mDEBUG\x1b[0m preparing client state\n" + `{"@value":{"datagrams":[{"datagram":{"@value":{"client_state_bytes":"client","consensus_state_bytes":"consensus"}}}]}}`)
	client, consensus, err := clientStatesFromCreate(body)
	if err != nil || client != "client" || consensus != "consensus" {
		t.Fatalf("got client=%q consensus=%q err=%v", client, consensus, err)
	}
	if _, _, err := clientStatesFromCreate([]byte("DEBUG only")); err == nil {
		t.Fatal("expected invalid non-JSON output to fail")
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
