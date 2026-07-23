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
	"os"
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
	Token, Sender, Voucher, Salt, Tag, Metadata string
	Decimals                                    uint8
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
	return c.PrepareToken(ctx, c.cfg.EVMTestERC20, 18, gnoChannel)
}

// PrepareToken validates a token and derives one fresh packet identity.
func (c *Client) PrepareToken(
	ctx context.Context,
	token string,
	decimals uint8,
	gnoChannel int64,
) (Plan, error) {
	token = strings.ToLower(token)
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
	rawDecimals, err := c.cast(ctx, "call", token, "decimals()(uint8)")
	decimalFields := strings.Fields(string(rawDecimals))
	if err != nil || len(decimalFields) == 0 ||
		decimalFields[0] != strconv.Itoa(int(decimals)) {
		return Plan{}, fmt.Errorf("ERC20 must report %d decimals", decimals)
	}
	salt, err := randomSalt()
	if err != nil {
		return Plan{}, err
	}
	tag := salt[2:]
	metadata, err := c.metadata(ctx, tag, sender, decimals)
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
		Token: token, Sender: sender, Voucher: "ibc/" + string(voucherHash[2:42]),
		Salt: salt, Tag: tag, Metadata: metadata, Decimals: decimals,
	}, nil
}

// WithFreshSalt returns the same token identity for another packet.
func (p Plan) WithFreshSalt() (Plan, error) {
	salt, err := randomSalt()
	if err != nil {
		return Plan{}, err
	}
	p.Salt = salt
	return p, nil
}

func randomSalt() (string, error) {
	salt := make([]byte, 32)
	if _, err := rand.Read(salt); err != nil {
		return "", errors.New("cannot generate packet salt")
	}
	return "0x" + hex.EncodeToString(salt), nil
}

// Mint submits one mint transaction.
func (c *Client) Mint(ctx context.Context, sender string) (string, error) {
	return c.MintToken(ctx, c.cfg.EVMTestERC20, sender, c.cfg.EVMTestAmount)
}

// MintToken submits one token mint transaction.
func (c *Client) MintToken(ctx context.Context, token, sender, amount string) (string, error) {
	receipt, err := c.receipt(
		ctx, "mint", "send", strings.ToLower(token),
		"mint(address,uint256)", sender, amount,
		"--private-key", c.cfg.EVMPrivateKey, "--json",
	)
	return receipt.TransactionHash, err
}

// Approve submits one approval transaction.
func (c *Client) Approve(ctx context.Context) (string, error) {
	return c.ApproveToken(ctx, c.cfg.EVMTestERC20, c.cfg.EVMTestAmount)
}

// ApproveToken submits one token approval transaction.
func (c *Client) ApproveToken(ctx context.Context, token, amount string) (string, error) {
	receipt, err := c.receipt(
		ctx, "approve", "send", strings.ToLower(token),
		"approve(address,uint256)", strings.ToLower(c.cfg.EVMZKGMContract), amount,
		"--private-key", c.cfg.EVMPrivateKey, "--json",
	)
	return receipt.TransactionHash, err
}

// Snapshot reads balances and the block before packet submission.
func (c *Client) Snapshot(ctx context.Context, sender string) (Snapshot, error) {
	return c.SnapshotToken(ctx, c.cfg.EVMTestERC20, sender)
}

// SnapshotToken reads token balances and the block before packet submission.
func (c *Client) SnapshotToken(ctx context.Context, token, sender string) (Snapshot, error) {
	senderBalance, escrowBalance, err := c.TokenBalances(ctx, token, sender)
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
	return c.TokenBalances(ctx, c.cfg.EVMTestERC20, sender)
}

// TokenBalances reads sender and escrow balances for one ERC20.
func (c *Client) TokenBalances(ctx context.Context, token, sender string) (string, string, error) {
	senderBalance, err := c.balance(ctx, token, sender)
	if err != nil {
		return "", "", err
	}
	escrowBalance, err := c.balance(ctx, token, strings.ToLower(c.cfg.EVMZKGMContract))
	return senderBalance, escrowBalance, err
}

func (c *Client) balance(ctx context.Context, token, account string) (string, error) {
	raw, err := c.cast(
		ctx, "call", strings.ToLower(token),
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

// DeployTestToken deploys the repository's mintable ERC20 fixture.
func (c *Client) DeployTestToken(
	ctx context.Context,
	name, symbol string,
	decimals uint8,
) (string, error) {
	outDir, err := os.MkdirTemp("", "union-erc20-*")
	if err != nil {
		return "", errors.New("cannot create ERC20 build directory")
	}
	defer os.RemoveAll(outDir)
	result, err := c.exec.Run(ctx, process.Command{
		Name: "forge",
		Args: []string{
			"create", "--root", c.cfg.ScriptDir, "--out", outDir, "--no-cache",
			"--rpc-url", c.cfg.EVMPacketRPCURL, "--private-key", c.cfg.EVMPrivateKey,
			"--broadcast", "--json", "fixtures/TestERC20.sol:TestERC20",
			"--constructor-args", name, symbol, strconv.Itoa(int(decimals)),
		},
	})
	if err != nil {
		return "", fmt.Errorf("ERC20 deployment failed: %w", err)
	}
	var response struct {
		DeployedTo string `json:"deployedTo"`
	}
	if json.Unmarshal(result.Stdout, &response) != nil ||
		!addressPattern.MatchString(strings.ToLower(response.DeployedTo)) {
		return "", errors.New("malformed ERC20 deployment response")
	}
	return strings.ToLower(response.DeployedTo), nil
}

func (c *Client) metadata(ctx context.Context, tag, authority string, decimals uint8) (string, error) {
	if len(tag) != 64 {
		return "", fmt.Errorf("malformed packet tag")
	}
	initializer, err := c.cast(
		ctx, "abi-encode", "f(address,address,string,string,uint8)",
		authority, strings.ToLower(c.cfg.EVMZKGMContract),
		"Union E2E "+tag[:32], "UE"+tag[:6], strconv.Itoa(int(decimals)),
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
