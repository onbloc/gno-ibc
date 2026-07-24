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

	"github.com/onbloc/gno-ibc/e2e/union/internal/process"
)

var qevalIntPattern = regexp.MustCompile(
	`^(?:height: [0-9]+\ndata: )?\(([0-9]+)[[:space:]]+int64\)[[:space:]]*$`,
)

const (
	DevSenderAddress  = "g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5"
	devSenderMnemonic = "source bonus chronic canvas draft south burst lottery vacant surface solve popular case indicate oppose farm nothing bullet exhibit title speed wink action roast"
)

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
