package main

import (
	"fmt"
	"io"
	"os"
	"strings"

	"github.com/gnolang/gno/tm2/pkg/crypto/bip39"
	"github.com/gnolang/gno/tm2/pkg/crypto/hd"
)

func main() {
	bz, err := io.ReadAll(os.Stdin)
	if err != nil || strings.TrimSpace(string(bz)) == "" {
		fmt.Fprintln(os.Stderr, "mnemonic is required on stdin")
		os.Exit(2)
	}
	key, err := derivePrivateKey(strings.TrimSpace(string(bz)))
	if err != nil {
		fmt.Fprintln(os.Stderr, "derive Gno private key:", err)
		os.Exit(1)
	}
	fmt.Printf("0x%x\n", key)
}

func derivePrivateKey(mnemonic string) ([32]byte, error) {
	master, chainCode := hd.ComputeMastersFromSeed(bip39.NewSeed(mnemonic, ""))
	return hd.DerivePrivateKeyForPath(master, chainCode, "44'/118'/0'/0/0")
}
