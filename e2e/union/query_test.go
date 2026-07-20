package unione2e

import "testing"

func TestParseUnionTxsTxHash(t *testing.T) {
	txs, err := parseUnionTxs([]byte(`{"txs":[{"txhash":"ABC123","height":"42"}]}`))
	if err != nil {
		t.Fatal(err)
	}
	if len(txs) != 1 || txs[0] != (UnionTx{Hash: "ABC123", Height: 42}) {
		t.Fatalf("transactions = %+v", txs)
	}
}
