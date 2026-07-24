package gno

import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"io"
	"os"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/gnolang/gno/tm2/pkg/crypto/keys"
	"github.com/gnolang/gno/tm2/pkg/crypto/secp256k1"
	"github.com/onbloc/gno-ibc/e2e/union/internal/process"
)

var qevalIntPattern = regexp.MustCompile(
	`^(?:height: [0-9]+\ndata: )?\(([0-9]+)[[:space:]]+int64\)[[:space:]]*$`,
)

const (
	DevSenderAddress  = "g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5"
	devSenderMnemonic = "source bonus chronic canvas draft south burst lottery vacant surface solve popular case indicate oppose farm nothing bullet exhibit title speed wink action roast"
)

// MembershipProofTx classifies one direct proof commitment submission.
type MembershipProofTx struct {
	Accepted       bool   `json:"accepted"`
	Classification string `json:"classification"`
}

// CommitMembershipProof submits one direct MsgRun with Voyager's configured
// raw relayer key.
func (c *Client) CommitMembershipProof(
	ctx context.Context,
	clientID, height int64,
	proof, path, value []byte,
) (MembershipProofTx, error) {
	keyBytes, err := hex.DecodeString(strings.TrimPrefix(c.cfg.GnoPrivateKey, "0x"))
	if err != nil || len(keyBytes) != 32 {
		return MembershipProofTx{}, fmt.Errorf("malformed Gno relayer key")
	}
	home, err := os.MkdirTemp("", "union-relayer-*")
	if err != nil {
		return MembershipProofTx{}, fmt.Errorf("cannot create Gno relayer keyring")
	}
	defer os.RemoveAll(home)
	keybase, err := keys.NewKeyBaseFromDir(home)
	if err != nil {
		return MembershipProofTx{}, fmt.Errorf("cannot create Gno relayer keyring")
	}
	var privateKey secp256k1.PrivKeySecp256k1
	copy(privateKey[:], keyBytes)
	if err := keybase.ImportPrivKey("relayer", privateKey, ""); err != nil {
		return MembershipProofTx{}, fmt.Errorf("cannot import Gno relayer key")
	}
	source := fmt.Sprintf(`package main

import (
	core %q
	types "gno.land/p/onbloc/ibc/union/types"
)

func main(cur realm) {
	core.CommitMembershipProof(cross(cur), types.NewMsgCommitMembershipProof(types.ClientId(%d), %d, %s, %s, %s))
}
`, c.cfg.GnoIBCCoreRealm, clientID, height, gnoBytes(proof), gnoBytes(path), gnoBytes(value))
	script := home + "/commit_membership_proof.gno"
	if err := os.WriteFile(script, []byte(source), 0o600); err != nil {
		return MembershipProofTx{}, fmt.Errorf("cannot write Gno proof transaction")
	}
	commandCtx := ctx
	cancel := func() {}
	if c.cfg.CommandTimeout > 0 {
		commandCtx, cancel = context.WithTimeout(ctx, c.cfg.CommandTimeout)
	}
	defer cancel()
	result, runErr := c.exec.Run(commandCtx, process.Command{
		Name: "gnokey",
		Args: []string{
			"maketx", "run", "-gas-fee", "10000000ugnot", "-gas-wanted", "1000000000",
			"-broadcast", "-chainid", c.cfg.GnoChainID, "-remote", c.cfg.GnoPacketRPCURL,
			"-insecure-password-stdin", "-home", home, "relayer", script,
		},
		Stdin: strings.NewReader("\n"),
	})
	if runErr == nil {
		return MembershipProofTx{Accepted: true, Classification: "accepted"}, nil
	}
	if commandCtx.Err() != nil {
		return MembershipProofTx{}, commandCtx.Err()
	}
	output := strings.ToLower(string(result.Stdout) + "\n" + string(result.Stderr))
	if containsAny(output, "unauthorized", "not authorized", "access denied", "permission denied") {
		return MembershipProofTx{}, fmt.Errorf("Gno relayer is not authorized")
	}
	if !containsAny(output, "proof", "mpt", "root", "hash mismatch", "invalid node") {
		return MembershipProofTx{}, fmt.Errorf("Gno proof transaction failed unexpectedly")
	}
	return MembershipProofTx{Classification: "proof verification rejected"}, nil
}

func gnoBytes(bz []byte) string {
	values := make([]string, len(bz))
	for i, value := range bz {
		values[i] = strconv.Itoa(int(value))
	}
	return "[]byte{" + strings.Join(values, ", ") + "}"
}

func containsAny(value string, needles ...string) bool {
	for _, needle := range needles {
		if strings.Contains(value, needle) {
			return true
		}
	}
	return false
}

// SendRaw broadcasts one direct EOA SendRaw call and returns its PacketSend.
func (c *Client) SendRaw(
	ctx context.Context,
	channel int64,
	operand, sendCoins string,
) (PacketSend, error) {
	before, err := c.latestEventHeight(ctx, "PacketSend", map[string]string{
		"source_channel_id": strconv.FormatInt(channel, 10),
	})
	if err != nil {
		return PacketSend{}, err
	}
	home, err := os.MkdirTemp("", "union-gnokey-*")
	if err != nil {
		return PacketSend{}, fmt.Errorf("cannot create Gno keyring")
	}
	defer os.RemoveAll(home)
	recoveryInput := strings.NewReader(devSenderMnemonic + "\n\n\n")
	if _, err := c.runGnokey(ctx, recoveryInput,
		"add", "-recover", "-insecure-password-stdin", "-home", home, "sender",
	); err != nil {
		return PacketSend{}, err
	}
	list, err := c.gnokey(ctx, "list", "-home", home)
	if err != nil {
		return PacketSend{}, err
	}
	if !strings.Contains(string(list), "addr: "+c.cfg.GnoRecipient+" ") {
		return PacketSend{}, fmt.Errorf("Gno sender fixture does not match GNO_RECIPIENT")
	}
	salt := make([]byte, 32)
	if _, err := rand.Read(salt); err != nil {
		return PacketSend{}, fmt.Errorf("cannot generate packet salt")
	}
	args := []string{
		"maketx", "call",
		"-pkgpath", c.cfg.GnoZKGMPort, "-func", "SendRaw",
		"-gas-fee", "5000000ugnot", "-gas-wanted", "200000000",
		"-broadcast", "-chainid", c.cfg.GnoChainID,
		"-remote", c.cfg.GnoPacketRPCURL,
		"-insecure-password-stdin", "-home", home,
	}
	if sendCoins != "" {
		args = append(args, "-send", sendCoins)
	}
	timeout := uint64(time.Now().Add(time.Hour).UnixNano())
	for _, arg := range []string{
		strconv.FormatInt(channel, 10), strconv.FormatUint(timeout, 10),
		hex.EncodeToString(salt), "2", "3", operand,
	} {
		args = append(args, "-args", arg)
	}
	args = append(args, "sender")
	if _, err := c.runGnokey(ctx, strings.NewReader("\n"), args...); err != nil {
		return PacketSend{}, err
	}
	return c.WaitPacketSend(ctx, channel, before)
}

func (c *Client) qeval(ctx context.Context, expression string) ([]byte, error) {
	return c.gnokey(
		ctx, "query", "vm/qeval", "-remote", c.cfg.GnoPacketRPCURL, "-data", expression,
	)
}

func (c *Client) qevalInt64(ctx context.Context, expression, label string) (int64, error) {
	raw, err := c.qeval(ctx, expression)
	if err != nil {
		return 0, err
	}
	match := qevalIntPattern.FindSubmatch(raw)
	if len(match) != 2 {
		return 0, fmt.Errorf("malformed Gno %s", label)
	}
	value, err := strconv.ParseInt(string(match[1]), 10, 64)
	if err != nil {
		return 0, fmt.Errorf("malformed Gno %s", label)
	}
	return value, nil
}

func (c *Client) gnokey(ctx context.Context, args ...string) ([]byte, error) {
	return c.runGnokey(ctx, nil, args...)
}

func (c *Client) runGnokey(ctx context.Context, stdin io.Reader, args ...string) ([]byte, error) {
	commandCtx := ctx
	cancel := func() {}
	if c.cfg.CommandTimeout > 0 {
		commandCtx, cancel = context.WithTimeout(ctx, c.cfg.CommandTimeout)
	}
	defer cancel()
	result, err := c.exec.Run(commandCtx, process.Command{
		Name: "gnokey", Args: args, Stdin: stdin,
	})
	if err != nil {
		if commandCtx.Err() != nil {
			return nil, commandCtx.Err()
		}
		return nil, fmt.Errorf("packet gnokey command failed: %w", err)
	}
	return bytes.TrimSpace(result.Stdout), nil
}
