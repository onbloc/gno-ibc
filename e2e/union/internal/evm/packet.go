package evm

import (
	"context"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"strconv"
	"strings"
	"time"
)

const (
	packetSendTopic  = "0x635b5d234fe7abddfb29b6c8498780a3" + "175c9002c537f20a3d1bf9d0e625b5fe"
	packetAckTopic   = "0x41d958a7d93b50b1f7541c6fc345d0c4" + "657b1e83497baa562c866611ac1f69bb"
	packetRecvTopic  = "0xe450e03249d131499e278eeafd8e27ef" + "fcceeb40b0b95628a087aa16b4b101d5"
	writeAckTopic    = "0x488830ba53f27b7033e966a79427476a" + "d47d550358e894bafeef8b97c6559251"
	createTokenTopic = "0x18469840730c2cbbd67b9f99f642166" + "7b07f0169a795be80a28f182d602daf5b"
)

type transactionReceipt struct {
	Status          string   `json:"status"`
	TransactionHash string   `json:"transactionHash"`
	Logs            []evmLog `json:"logs"`
}

type evmLog struct {
	Address         string   `json:"address"`
	Topics          []string `json:"topics"`
	Data            string   `json:"data"`
	TransactionHash string   `json:"transactionHash"`
}

// SendResult identifies the one submitted packet.
type SendResult struct {
	Tx, PacketHash string
}

// Acknowledgement is one observed EVM PacketAck.
type Acknowledgement struct {
	Tx, Value string
}

// Receive is one EVM receive/write-ack transaction.
type Receive struct {
	Tx, Acknowledgement string
}

// TokenOrder is the ABI payload for one ZKGM token operation.
type TokenOrder struct {
	Sender, Receiver, BaseToken, Amount, QuoteToken, Metadata string
	Kind                                                      uint8
}

// EncodeTokenOrder ABI-encodes one explicit TokenOrder.
func (c *Client) EncodeTokenOrder(ctx context.Context, order TokenOrder) (string, error) {
	raw, err := c.cast(
		ctx, "abi-encode", "f(bytes,bytes,bytes,uint256,bytes,uint256,uint8,bytes)",
		order.Sender, order.Receiver, order.BaseToken, order.Amount, order.QuoteToken,
		order.Amount, strconv.Itoa(int(order.Kind)), order.Metadata,
	)
	return string(raw), err
}

// Send submits one TokenOrder and extracts exactly one PacketSend.
func (c *Client) Send(
	ctx context.Context,
	evmChannel int64,
	sender, recipient, voucher, salt, tag string,
) (SendResult, error) {
	metadata, err := c.metadata(ctx, tag, sender, 18)
	if err != nil {
		return SendResult{}, err
	}
	return c.sendTokenOrder(
		ctx, evmChannel, c.cfg.EVMTestERC20, sender, recipient, voucher,
		c.cfg.EVMTestAmount, salt, 0, metadata,
	)
}

// SendTokenOrder submits one explicitly typed TokenOrder.
func (c *Client) SendTokenOrder(
	ctx context.Context,
	evmChannel int64,
	plan Plan,
	recipient, amount string,
	kind uint8,
) (SendResult, error) {
	return c.sendTokenOrder(
		ctx, evmChannel, plan.Token, plan.Sender, recipient, plan.Voucher,
		amount, plan.Salt, kind, plan.Metadata,
	)
}

func (c *Client) sendTokenOrder(
	ctx context.Context,
	evmChannel int64,
	token, sender, recipient, voucher, amount, salt string,
	kind uint8,
	metadata string,
) (SendResult, error) {
	operand, err := c.EncodeTokenOrder(
		ctx, TokenOrder{
			Sender: sender, Receiver: "0x" + hex.EncodeToString([]byte(recipient)),
			BaseToken: strings.ToLower(token), Amount: amount,
			QuoteToken: "0x" + hex.EncodeToString([]byte(voucher)),
			Kind:       kind, Metadata: metadata,
		},
	)
	if err != nil {
		return SendResult{}, err
	}
	timeout := (time.Now().Unix() + 3600) * 1_000_000_000
	receipt, err := c.receipt(
		ctx, "packet", "send", strings.ToLower(c.cfg.EVMZKGMContract),
		"send(uint32,uint64,uint64,bytes32,(uint8,uint8,bytes))",
		strconv.FormatInt(evmChannel, 10), "0", strconv.FormatInt(timeout, 10),
		salt, "(2,3,"+operand+")", "--private-key", c.cfg.EVMPrivateKey, "--json",
	)
	if err != nil {
		return SendResult{}, err
	}
	hash, err := packetHashFromReceipt(receipt, c.cfg.EVMIBCHandler, evmChannel)
	if err != nil {
		return SendResult{}, err
	}
	return SendResult{Tx: receipt.TransactionHash, PacketHash: hash}, nil
}

// BlockNumber returns the current EVM execution height.
func (c *Client) BlockNumber(ctx context.Context) (uint64, error) {
	raw, err := c.cast(ctx, "block-number")
	if err != nil {
		return 0, err
	}
	block, err := strconv.ParseUint(string(raw), 10, 64)
	if err != nil {
		return 0, errors.New("malformed EVM block number")
	}
	return block, nil
}

// CodeExists reports whether an EVM account has deployed bytecode.
func (c *Client) CodeExists(ctx context.Context, address string) (bool, error) {
	raw, err := c.cast(ctx, "code", strings.ToLower(address))
	if err != nil {
		return false, err
	}
	return string(raw) != "0x" && codePattern.Match(raw), nil
}

// WrappedTokenCreatedCount counts matching wrapped-token creation logs.
func (c *Client) WrappedTokenCreatedCount(
	ctx context.Context,
	fromBlock uint64,
	channel int64,
	token string,
) (int, error) {
	filter, _ := json.Marshal(map[string]any{
		"address":   c.cfg.EVMZKGMContract,
		"fromBlock": fmt.Sprintf("0x%x", fromBlock),
		"toBlock":   "latest",
		"topics": []string{
			createTokenTopic,
			fmt.Sprintf("0x%064x", channel),
			"0x" + strings.Repeat("0", 24) + strings.TrimPrefix(strings.ToLower(token), "0x"),
		},
	})
	raw, err := c.cast(ctx, "rpc", "eth_getLogs", string(filter))
	if err != nil {
		return 0, err
	}
	var logs []evmLog
	if json.Unmarshal(raw, &logs) != nil {
		return 0, errors.New("malformed CreateWrappedToken log response")
	}
	return len(logs), nil
}

// WaitReceive requires exactly one PacketRecv and WriteAck in one EVM transaction.
func (c *Client) WaitReceive(
	ctx context.Context,
	fromBlock uint64,
	channel int64,
	packetHash string,
) (Receive, error) {
	filter, _ := json.Marshal(map[string]any{
		"address":   c.cfg.EVMIBCHandler,
		"fromBlock": fmt.Sprintf("0x%x", fromBlock),
		"toBlock":   "latest",
		"topics": []any{
			[]string{packetRecvTopic, writeAckTopic},
			fmt.Sprintf("0x%064x", channel),
			packetHash,
		},
	})
	waitCtx, cancel := context.WithTimeout(ctx, c.cfg.ScenarioTimeout)
	defer cancel()
	for {
		raw, err := c.cast(waitCtx, "rpc", "eth_getLogs", string(filter))
		if err != nil {
			return Receive{}, err
		}
		var logs []evmLog
		if json.Unmarshal(raw, &logs) != nil {
			return Receive{}, errors.New("malformed EVM receive log response")
		}
		var receives, writes []evmLog
		for _, log := range logs {
			if len(log.Topics) == 0 {
				continue
			}
			switch strings.ToLower(log.Topics[0]) {
			case packetRecvTopic:
				receives = append(receives, log)
			case writeAckTopic:
				writes = append(writes, log)
			}
		}
		if len(receives) > 1 || len(writes) > 1 {
			return Receive{}, fmt.Errorf(
				"EVM receive counts PacketRecv=%d WriteAck=%d, want one each",
				len(receives), len(writes),
			)
		}
		if len(receives) == 0 || len(writes) == 0 {
			if err := pause(waitCtx, c.cfg.PollInterval); err != nil {
				return Receive{}, fmt.Errorf("EVM receive was not visible: %w", err)
			}
			continue
		}
		if receives[0].TransactionHash != writes[0].TransactionHash ||
			!hashPattern.MatchString(receives[0].TransactionHash) {
			return Receive{}, errors.New("EVM PacketRecv and WriteAck transactions differ")
		}
		ack, err := c.cast(waitCtx, "decode-abi", "f()(bytes)", writes[0].Data, "--json")
		var values []string
		if err != nil || json.Unmarshal(ack, &values) != nil ||
			len(values) != 1 || !validHex(values[0]) {
			return Receive{}, errors.New("malformed EVM WriteAck acknowledgement")
		}
		return Receive{Tx: receives[0].TransactionHash, Acknowledgement: values[0]}, nil
	}
}

func packetHashFromReceipt(receipt transactionReceipt, handler string, channel int64) (string, error) {
	channelTopic := fmt.Sprintf("0x%064x", channel)
	var matches []evmLog
	for _, log := range receipt.Logs {
		if !strings.EqualFold(log.Address, handler) || len(log.Topics) == 0 ||
			!strings.EqualFold(log.Topics[0], packetSendTopic) {
			continue
		}
		matches = append(matches, log)
	}
	if len(matches) != 1 {
		return "", errors.New("PacketSend count is not one")
	}
	if len(matches[0].Topics) < 3 ||
		!strings.EqualFold(matches[0].Topics[1], channelTopic) ||
		!hashPattern.MatchString(matches[0].Topics[2]) {
		return "", errors.New("malformed PacketSend log")
	}
	return matches[0].Topics[2], nil
}

// WaitAcknowledgement polls for exactly one matching PacketAck.
func (c *Client) WaitAcknowledgement(
	ctx context.Context,
	fromBlock uint64,
	channel int64,
	packetHash string,
) (Acknowledgement, error) {
	filter, _ := json.Marshal(map[string]any{
		"address":   c.cfg.EVMIBCHandler,
		"fromBlock": fmt.Sprintf("0x%x", fromBlock),
		"toBlock":   "latest",
		"topics": []string{
			packetAckTopic, fmt.Sprintf("0x%064x", channel), packetHash,
		},
	})
	waitCtx, cancel := context.WithTimeout(ctx, c.cfg.ScenarioTimeout)
	defer cancel()
	for {
		raw, err := c.cast(waitCtx, "rpc", "eth_getLogs", string(filter))
		if err != nil {
			return Acknowledgement{}, err
		}
		var logs []evmLog
		if json.Unmarshal(raw, &logs) != nil {
			return Acknowledgement{}, errors.New("malformed EVM PacketAck log response")
		}
		switch len(logs) {
		case 0:
			if err := pause(waitCtx, c.cfg.PollInterval); err != nil {
				return Acknowledgement{}, fmt.Errorf("EVM PacketAck was not visible: %w", err)
			}
		case 1:
			return c.decodeAcknowledgement(waitCtx, logs[0], channel, packetHash)
		default:
			return Acknowledgement{}, fmt.Errorf("EVM PacketAck count=%d, want exactly one", len(logs))
		}
	}
}

func (c *Client) decodeAcknowledgement(
	ctx context.Context,
	log evmLog,
	channel int64,
	packetHash string,
) (Acknowledgement, error) {
	if !strings.EqualFold(log.Address, c.cfg.EVMIBCHandler) ||
		len(log.Topics) < 3 ||
		!strings.EqualFold(log.Topics[0], packetAckTopic) ||
		!strings.EqualFold(log.Topics[1], fmt.Sprintf("0x%064x", channel)) ||
		!strings.EqualFold(log.Topics[2], packetHash) ||
		!hashPattern.MatchString(log.TransactionHash) ||
		!validHex(log.Data) {
		return Acknowledgement{}, errors.New("malformed EVM PacketAck log")
	}
	raw, err := c.cast(ctx, "decode-abi", "f()(bytes)", log.Data, "--json")
	if err != nil {
		return Acknowledgement{}, err
	}
	var values []string
	if json.Unmarshal(raw, &values) != nil || len(values) != 1 || !validHex(values[0]) {
		return Acknowledgement{}, errors.New("malformed EVM acknowledgement")
	}
	return Acknowledgement{Tx: log.TransactionHash, Value: values[0]}, nil
}

// PacketCommitmentPath returns the commitment key for one packet.
func (c *Client) PacketCommitmentPath(ctx context.Context, packetHash string) (string, error) {
	path, err := c.cast(ctx, "abi-encode", "f(uint256,bytes32)", "4", packetHash)
	if err != nil {
		return "", err
	}
	key, err := c.cast(ctx, "keccak", string(path))
	if err != nil || !hashPattern.Match(key) {
		return "", errors.New("malformed packet commitment key")
	}
	return string(key), nil
}

// VerifyCommitmentCleared requires the Union non-membership sentinel.
func (c *Client) VerifyCommitmentCleared(ctx context.Context, packetHash string) error {
	key, err := c.PacketCommitmentPath(ctx, packetHash)
	if err != nil {
		return err
	}
	value, err := c.cast(
		ctx, "call", c.cfg.EVMIBCHandler, "commitments(bytes32)(bytes32)", key,
	)
	if err != nil {
		return err
	}
	if !strings.EqualFold(string(value), "0x02"+strings.Repeat("0", 62)) {
		return errors.New("EVM packet commitment is still active")
	}
	return nil
}

func validHex(value string) bool {
	value = strings.TrimPrefix(value, "0x")
	if value == "" || len(value)%2 != 0 {
		return false
	}
	_, err := hex.DecodeString(value)
	return err == nil
}

func pause(ctx context.Context, interval time.Duration) error {
	if interval <= 0 {
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
			return nil
		}
	}
	timer := time.NewTimer(interval)
	defer timer.Stop()
	select {
	case <-ctx.Done():
		return ctx.Err()
	case <-timer.C:
		return nil
	}
}
