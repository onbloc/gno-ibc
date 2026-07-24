package union_test

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/onbloc/gno-ibc/e2e/union/internal/config"
	"github.com/onbloc/gno-ibc/e2e/union/internal/union"
)

func TestMembershipHeightMatchesPacketPath(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, request *http.Request) {
		if request.Method != http.MethodPost {
			http.Error(w, "method", http.StatusMethodNotAllowed)
			return
		}
		_, _ = w.Write([]byte(`{"jsonrpc":"2.0","id":1,"result":{"txs":[` +
			`{"tx_result":{"events":[{"type":"wasm-commit_membership_proof","attributes":[` +
			`{"key":"client_id","value":"22"},{"key":"proof_height","value":"12"},` +
			`{"key":"path","value":"abcd"}]}]}}]}}`))
	}))
	defer server.Close()
	c := union.New(config.Config{
		UnionPacketRPCURL: server.URL, CommandTimeout: time.Second,
	})
	height, err := c.MembershipHeight(context.Background(), 22, 11, "0xabcd")
	if err != nil {
		t.Fatal(err)
	}
	if height != 12 {
		t.Fatalf("height = %d, want 12", height)
	}
}
