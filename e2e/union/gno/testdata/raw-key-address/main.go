package main

import (
	"encoding/hex"
	"fmt"
	"os"
	"strings"

	"github.com/gnolang/gno/tm2/pkg/crypto/secp256k1"
)

func main() {
	if len(os.Args) != 2 {
		fmt.Fprintln(os.Stderr, "usage: raw-key-address <hex-private-key>")
		os.Exit(2)
	}
	bz, err := hex.DecodeString(strings.TrimPrefix(os.Args[1], "0x"))
	if err != nil || len(bz) != 32 {
		fmt.Fprintln(os.Stderr, "private key must be 32-byte hex")
		os.Exit(2)
	}
	key := secp256k1.PrivKeySecp256k1(bz)
	fmt.Println(key.PubKey().Address())
}
