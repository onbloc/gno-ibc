// Package evm owns direct EVM packet operations for the Union E2E runner.
package evm

import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"math/big"
	"regexp"
	"strconv"
	"strings"

	"github.com/onbloc/gno-ibc/e2e/union/internal/config"
	"github.com/onbloc/gno-ibc/e2e/union/internal/process"
)

var (
	addressPattern = regexp.MustCompile(`^0x[0-9a-f]{40}$`)
	hashPattern    = regexp.MustCompile(`^0x[0-9a-fA-F]{64}$`)
	codePattern    = regexp.MustCompile(`^0x[0-9a-fA-F]+$`)
)

// Client executes cast against the configured packet RPC.
type Client struct {
	cfg  config.Config
	exec process.Executor
}

// Plan is the durable identity needed to reconstruct one TokenOrder.
type Plan struct {
	Sender, Voucher, Salt, Tag string
}

// Snapshot captures the source balances and search boundary before send.
type Snapshot struct {
	Sender, Escrow string
	Block          uint64
}

// New returns a concrete EVM packet client.
func New(cfg config.Config) *Client {
	return NewWithExecutor(cfg, process.OSExecutor{})
}

// NewWithExecutor returns a client using the supplied command seam.
func NewWithExecutor(cfg config.Config, executor process.Executor) *Client {
	return &Client{cfg: cfg, exec: executor}
}

// Prepare validates the token and derives one fresh packet identity.
func (c *Client) Prepare(ctx context.Context, gnoChannel int64) (Plan, error) {
	token := strings.ToLower(c.cfg.EVMTestERC20)
	raw, err := c.cast(ctx, "wallet", "address", "--private-key", c.cfg.EVMPrivateKey)
	if err != nil {
		return Plan{}, err
	}
	sender := strings.ToLower(string(raw))
	if !addressPattern.MatchString(sender) {
		return Plan{}, fmt.Errorf("cannot derive EVM sender")
	}
	code, err := c.cast(ctx, "code", token)
	if err != nil {
		return Plan{}, err
	}
	if string(code) == "0x" || !codePattern.Match(code) {
		return Plan{}, errors.New("EVM_TEST_ERC20 has no deployed code")
	}
	decimals, err := c.cast(ctx, "call", token, "decimals()(uint8)")
	decimalFields := strings.Fields(string(decimals))
	if err != nil || len(decimalFields) == 0 || decimalFields[0] != "18" {
		return Plan{}, errors.New("EVM_TEST_ERC20 must report 18 decimals")
	}
	saltBytes := make([]byte, 32)
	if _, err := rand.Read(saltBytes); err != nil {
		return Plan{}, errors.New("cannot generate packet salt")
	}
	salt := "0x" + hex.EncodeToString(saltBytes)
	tag := salt[2:]
	metadata, err := c.metadata(ctx, tag, sender)
	if err != nil {
		return Plan{}, err
	}
	image, err := c.cast(ctx, "keccak", metadata)
	if err != nil || !hashPattern.Match(image) {
		return Plan{}, errors.New("malformed packet metadata hash")
	}
	prediction, err := c.cast(
		ctx, "abi-encode", "f(uint256,uint32,bytes,uint256)",
		"0", strconv.FormatInt(gnoChannel, 10), token, string(image),
	)
	if err != nil {
		return Plan{}, err
	}
	voucherHash, err := c.cast(ctx, "keccak", string(prediction))
	if err != nil || !hashPattern.Match(voucherHash) {
		return Plan{}, errors.New("malformed packet voucher hash")
	}
	return Plan{
		Sender: sender, Voucher: "ibc/" + string(voucherHash[2:42]), Salt: salt, Tag: tag,
	}, nil
}

// Mint submits one mint transaction.
func (c *Client) Mint(ctx context.Context, sender string) (string, error) {
	receipt, err := c.receipt(
		ctx, "mint", "send", strings.ToLower(c.cfg.EVMTestERC20),
		"mint(address,uint256)", sender, c.cfg.EVMTestAmount,
		"--private-key", c.cfg.EVMPrivateKey, "--json",
	)
	return receipt.TransactionHash, err
}

// Approve submits one approval transaction.
func (c *Client) Approve(ctx context.Context) (string, error) {
	receipt, err := c.receipt(
		ctx, "approve", "send", strings.ToLower(c.cfg.EVMTestERC20),
		"approve(address,uint256)", strings.ToLower(c.cfg.EVMZKGMContract), c.cfg.EVMTestAmount,
		"--private-key", c.cfg.EVMPrivateKey, "--json",
	)
	return receipt.TransactionHash, err
}

// Snapshot reads balances and the block before packet submission.
func (c *Client) Snapshot(ctx context.Context, sender string) (Snapshot, error) {
	senderBalance, escrowBalance, err := c.Balances(ctx, sender)
	if err != nil {
		return Snapshot{}, err
	}
	raw, err := c.cast(ctx, "block-number")
	if err != nil {
		return Snapshot{}, err
	}
	block, err := strconv.ParseUint(string(raw), 10, 64)
	if err != nil {
		return Snapshot{}, errors.New("malformed EVM block number")
	}
	return Snapshot{Sender: senderBalance, Escrow: escrowBalance, Block: block}, nil
}

// Balances reads sender and escrow ERC20 balances.
func (c *Client) Balances(ctx context.Context, sender string) (string, string, error) {
	senderBalance, err := c.balance(ctx, sender)
	if err != nil {
		return "", "", err
	}
	escrowBalance, err := c.balance(ctx, strings.ToLower(c.cfg.EVMZKGMContract))
	return senderBalance, escrowBalance, err
}

func (c *Client) balance(ctx context.Context, account string) (string, error) {
	raw, err := c.cast(
		ctx, "call", strings.ToLower(c.cfg.EVMTestERC20),
		"balanceOf(address)(uint256)", account,
	)
	if err != nil {
		return "", err
	}
	fields := strings.Fields(string(raw))
	if len(fields) == 0 {
		return "", errors.New("malformed ERC20 balance")
	}
	value, ok := new(big.Int).SetString(fields[0], 10)
	if !ok || value.Sign() < 0 || value.String() != fields[0] {
		return "", errors.New("malformed ERC20 balance")
	}
	return fields[0], nil
}

func (c *Client) metadata(ctx context.Context, tag, authority string) (string, error) {
	if len(tag) != 64 {
		return "", fmt.Errorf("malformed packet tag")
	}
	initializer, err := c.cast(
		ctx, "abi-encode", "f(address,address,string,string,uint8)",
		authority, strings.ToLower(c.cfg.EVMZKGMContract),
		"Union E2E "+tag[:32], "UE"+tag[:6], "18",
	)
	if err != nil {
		return "", err
	}
	initializer = append([]byte("0x8420ce99"), bytes.TrimPrefix(initializer, []byte("0x"))...)
	metadata, err := c.cast(ctx, "abi-encode", "f(bytes,bytes)", "0x6772633230", string(initializer))
	return string(metadata), err
}

func (c *Client) receipt(ctx context.Context, label string, args ...string) (transactionReceipt, error) {
	raw, err := c.cast(ctx, args...)
	if err != nil {
		return transactionReceipt{}, err
	}
	var receipt transactionReceipt
	if json.Unmarshal(raw, &receipt) != nil || receipt.Status != "0x1" ||
		!hashPattern.MatchString(receipt.TransactionHash) {
		return transactionReceipt{}, fmt.Errorf("ERC20 %s transaction failed", label)
	}
	return receipt, nil
}

func (c *Client) cast(ctx context.Context, args ...string) ([]byte, error) {
	commandCtx := ctx
	cancel := func() {}
	if c.cfg.CommandTimeout > 0 {
		commandCtx, cancel = context.WithTimeout(ctx, c.cfg.CommandTimeout)
	}
	defer cancel()
	result, err := c.exec.Run(commandCtx, process.Command{
		Name: "cast", Args: args, Env: []string{"ETH_RPC_URL=" + c.cfg.EVMPacketRPCURL},
	})
	if err != nil {
		if commandCtx.Err() != nil {
			return nil, commandCtx.Err()
		}
		action := "unknown"
		if len(args) != 0 {
			action = args[0]
		}
		return nil, fmt.Errorf("packet cast command failed: %s: %w", action, err)
	}
	return bytes.TrimSpace(result.Stdout), nil
}
