// Package gno owns direct Gno packet queries for the Union E2E runner.
package gno

import (
	"bytes"
	"context"
	"fmt"
	"regexp"
	"strconv"

	"github.com/onbloc/gno-ibc/e2e/union/internal/config"
	"github.com/onbloc/gno-ibc/e2e/union/internal/process"
)

var qevalIntPattern = regexp.MustCompile(
	`^(?:height: [0-9]+\ndata: )?\(([0-9]+)[[:space:]]+int64\)[[:space:]]*$`,
)

// Client queries Gno and its transaction indexer.
type Client struct {
	cfg  config.Config
	exec process.Executor
}

// New returns a concrete Gno packet client.
func New(cfg config.Config) *Client {
	return NewWithExecutor(cfg, process.OSExecutor{})
}

// NewWithExecutor returns a client using the supplied command seam.
func NewWithExecutor(cfg config.Config, executor process.Executor) *Client {
	return &Client{cfg: cfg, exec: executor}
}

// VoucherBalance returns one GRC20 voucher balance.
func (c *Client) VoucherBalance(ctx context.Context, voucher, recipient string) (int64, error) {
	expression := fmt.Sprintf(
		`%s.VoucherBalanceOf("%s",address("%s"))`, c.cfg.GnoZKGMPort, voucher, recipient,
	)
	raw, err := c.gnokey(ctx, "query", "vm/qeval", "-remote", c.cfg.GnoPacketRPCURL, "-data", expression)
	if err != nil {
		return 0, err
	}
	match := qevalIntPattern.FindSubmatch(raw)
	if len(match) != 2 {
		return 0, fmt.Errorf("malformed Gno voucher balance")
	}
	value, err := strconv.ParseInt(string(match[1]), 10, 64)
	if err != nil {
		return 0, fmt.Errorf("malformed Gno voucher balance")
	}
	return value, nil
}

func (c *Client) gnokey(ctx context.Context, args ...string) ([]byte, error) {
	commandCtx := ctx
	cancel := func() {}
	if c.cfg.CommandTimeout > 0 {
		commandCtx, cancel = context.WithTimeout(ctx, c.cfg.CommandTimeout)
	}
	defer cancel()
	result, err := c.exec.Run(commandCtx, process.Command{Name: "gnokey", Args: args})
	if err != nil {
		if commandCtx.Err() != nil {
			return nil, commandCtx.Err()
		}
		return nil, fmt.Errorf("packet gnokey command failed: %w", err)
	}
	return bytes.TrimSpace(result.Stdout), nil
}
