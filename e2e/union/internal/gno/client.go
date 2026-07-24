// Package gno owns direct Gno packet queries for the Union E2E runner.
package gno

import (
	"context"
	"fmt"
	"regexp"
	"strconv"
	"strings"

	"github.com/onbloc/gno-ibc/e2e/union/internal/config"
	"github.com/onbloc/gno-ibc/e2e/union/internal/process"
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
	return c.qevalInt64(ctx, expression, "voucher balance")
}

// VoucherTotalSupply returns one registered GRC20 voucher supply.
func (c *Client) VoucherTotalSupply(ctx context.Context, registryKey string) (int64, error) {
	expression := fmt.Sprintf(
		`gno.land/r/demo/defi/grc20reg.MustGet("%s").TotalSupply()`, registryKey,
	)
	return c.qevalInt64(ctx, expression, "voucher total supply")
}

// NativeBalance returns one account's balance for a native denom.
func (c *Client) NativeBalance(ctx context.Context, owner, denom string) (int64, error) {
	raw, err := c.gnokey(
		ctx, "query", "bank/balances/"+owner, "-remote", c.cfg.GnoPacketRPCURL,
	)
	if err != nil {
		return 0, err
	}
	for _, line := range strings.Split(string(raw), "\n") {
		line = strings.TrimSpace(line)
		if !strings.HasPrefix(line, `data: "`) {
			continue
		}
		for _, coin := range strings.Split(strings.TrimSuffix(strings.TrimPrefix(line, `data: "`), `"`), ",") {
			coin = strings.TrimSpace(coin)
			coinDenom := strings.TrimLeft(coin, "0123456789")
			if coinDenom != denom {
				continue
			}
			value, err := strconv.ParseInt(strings.TrimSuffix(coin, coinDenom), 10, 64)
			if err != nil || value < 0 {
				return 0, fmt.Errorf("malformed Gno native balance")
			}
			return value, nil
		}
		return 0, nil
	}
	return 0, fmt.Errorf("malformed Gno native balance")
}

// ProxyAddress returns the ZKGM proxy's banker address.
func (c *Client) ProxyAddress(ctx context.Context) (string, error) {
	raw, err := c.qeval(ctx, c.cfg.GnoZKGMPort+".ProxyAddress()")
	if err != nil {
		return "", err
	}
	match := regexp.MustCompile(`\("(g1[0-9a-z]{38})"[[:space:]]+[^)]+\)`).FindSubmatch(raw)
	if len(match) != 2 {
		return "", fmt.Errorf("malformed Gno proxy address")
	}
	return string(match[1]), nil
}

// VerifyCommitmentCleared requires the acknowledged Gno packet sentinel.
func (c *Client) VerifyCommitmentCleared(ctx context.Context, packetHash string) error {
	hash := strings.TrimPrefix(packetHash, "0x")
	if len(hash) != 64 {
		return fmt.Errorf("malformed packet hash")
	}
	raw, err := c.qeval(
		ctx,
		fmt.Sprintf(
			`gno.land/r/onbloc/ibc/union/testing/e2e_setup.QueryBatchPacketCommitment("%s")`,
			hash,
		),
	)
	if err != nil {
		return err
	}
	if !strings.Contains(string(raw), "0x02"+strings.Repeat("00", 31)) {
		return fmt.Errorf("Gno packet commitment is still active")
	}
	return nil
}
