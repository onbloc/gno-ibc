package main

import (
	"testing"

	"github.com/gnolang/gno/tm2/pkg/crypto/secp256k1"
)

func TestDerivePrivateKey(t *testing.T) {
	key, err := derivePrivateKey("source bonus chronic canvas draft south burst lottery vacant surface solve popular case indicate oppose farm nothing bullet exhibit title speed wink action roast")
	if err != nil {
		t.Fatal(err)
	}
	if got, want := secp256k1.PrivKeySecp256k1(key[:]).PubKey().Address().String(), "g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5"; got != want {
		t.Fatalf("derived address %s, want %s", got, want)
	}
}
