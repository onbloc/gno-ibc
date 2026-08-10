// Command proof_submit is the narrow signing bridge for the Python runner.
// gnokey cannot import Voyager's raw Gno key, so this command owns only that
// conversion and one direct MsgRun submission.
package main

import (
	"encoding/hex"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/gnolang/gno/tm2/pkg/crypto/keys"
	"github.com/gnolang/gno/tm2/pkg/crypto/secp256k1"
)

func main() {
	if len(os.Args) != 9 {
		fmt.Fprintln(os.Stderr, "usage: proof_submit <core> <client> <height> <proof> <path> <value> <chain> <rpc>")
		os.Exit(2)
	}
	rawKey, readErr := io.ReadAll(io.LimitReader(os.Stdin, 256))
	key, err := hex.DecodeString(strings.TrimPrefix(strings.TrimSpace(string(rawKey)), "0x"))
	client, clientErr := strconv.ParseInt(os.Args[2], 10, 64)
	height, heightErr := strconv.ParseInt(os.Args[3], 10, 64)
	proof, proofErr := hex.DecodeString(os.Args[4])
	path, pathErr := hex.DecodeString(os.Args[5])
	value, valueErr := hex.DecodeString(os.Args[6])
	if err != nil || len(key) != 32 || clientErr != nil || heightErr != nil ||
		proofErr != nil || pathErr != nil || valueErr != nil || readErr != nil {
		fmt.Fprintln(os.Stderr, "malformed proof submission argument")
		os.Exit(2)
	}
	home, err := os.MkdirTemp("", "union-relayer-")
	if err != nil {
		panic(err)
	}
	defer os.RemoveAll(home)
	keybase, err := keys.NewKeyBaseFromDir(home)
	if err != nil {
		panic(err)
	}
	var private secp256k1.PrivKeySecp256k1
	copy(private[:], key)
	if err := keybase.ImportPrivKey("relayer", private, ""); err != nil {
		panic(err)
	}
	source := fmt.Sprintf(`package main

import (
	core %q
	types "gno.land/p/onbloc/ibc/union/types"
)

func main(cur realm) {
	core.CommitMembershipProof(cross(cur), types.NewMsgCommitMembershipProof(types.ClientId(%d), %d, %s, %s, %s))
}
`, os.Args[1], client, height, bytesLiteral(proof), bytesLiteral(path), bytesLiteral(value))
	script := filepath.Join(home, "commit_membership_proof.gno")
	if err := os.WriteFile(script, []byte(source), 0o600); err != nil {
		panic(err)
	}
	command := exec.Command("gnokey", "maketx", "run", "-gas-fee", "10000000ugnot",
		"-gas-wanted", "1000000000", "-broadcast", "-chainid", os.Args[7],
		"-remote", os.Args[8], "-insecure-password-stdin", "-home", home, "relayer", script)
	command.Stdin = strings.NewReader("\n")
	command.Stdout = os.Stdout
	command.Stderr = os.Stderr
	if err := command.Run(); err != nil {
		os.Exit(1)
	}
}

func bytesLiteral(value []byte) string {
	parts := make([]string, len(value))
	for index, item := range value {
		parts[index] = strconv.Itoa(int(item))
	}
	return "[]byte{" + strings.Join(parts, ",") + "}"
}
