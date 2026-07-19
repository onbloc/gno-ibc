package ics20zkgm_adapter

import (
	"crypto/sha256"
	"encoding/binary"
	"encoding/hex"
	"strconv"
	"time"

	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/fqname/v0"
	types "gno.land/p/onbloc/ibc/union/types"
	z "gno.land/p/onbloc/ibc/union/zkgm"
	"gno.land/r/aib/ibc/apps/transfer"
	adapter "gno.land/r/onbloc/ibc/union/apps/ics20zkgm_adapter"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
)

// defaultForwardTimeout bounds the outbound ZKGM packet's own expiry when the
// memo omits (or has an unparseable) timeout. On timeout the escrowed
// voucher refunds to this adapter, not the original AtomOne sender.
const defaultForwardTimeout = 24 * time.Hour

// OnTransferRecv implements adapter.IImpl. Forward direction: AtomOne -> EVM.
//
// Always uses Kind = TOKEN_ORDER_KIND_INITIALIZE, never ESCROW: resending
// INITIALIZE for an already-deployed wrapped token is an idempotent mint-only
// no-op, while ESCROW reverts if the token isn't deployed yet.
func (i *Impl) OnTransferRecv(_ int, rlm realm, sourceClient string, sequence uint64, data transfer.FungibleTokenPacketData, denom transfer.Denom) error {
	memo, ok := parseForwardMemo(data.Memo)
	if !ok {
		return nil
	}

	// The mint must have landed on this adapter — the real recipient lives
	// in memo.Receiver, not data.Receiver.
	if data.Receiver != rlm.Address().String() {
		return makeError(errReceiverNotAdapter, data.Receiver, rlm.Address().String())
	}

	cfg, found := i.store.GetDenomConfig(denom.Base)
	if !found {
		return makeError(errDenomNotRegistered, denom.Base)
	}

	amount, err := strconv.ParseInt(data.Amount, 10, 64)
	if err != nil {
		return makeError(errInvalidAmount, data.Amount, err.Error())
	}

	receiver, err := parseHexBytes(memo.Receiver)
	if err != nil {
		return makeError(errInvalidReceiver, memo.Receiver, err.Error())
	}

	// Approve zkgm's proxy to pull the just-minted voucher out of this
	// adapter's own balance (Send()'s escrow step uses TransferFrom).
	voucherDenom := denom.IBCDenom()
	transfer.VoucherApprove(cross(rlm), voucherDenom, zkgm.ProxyAddress(), amount)

	// TODO(relayer-fee): QuoteAmount == BaseAmount, no relayer fee taken yet.
	// Revisit once a fee policy for hook-initiated forwards is decided.
	baseAmount := u256.NewUintFromInt64(amount)
	quoteAmount := u256.NewUintFromInt64(amount)

	// grc20reg keys are qualified by the registering realm's own pkgpath
	// (see transfer.PkgPath's doc comment) -- the bare hash alone wouldn't
	// resolve, and ZKGM would misclassify this voucher as a native coin.
	baseToken := fqname.Construct(transfer.PkgPath(), denom.HashHex())

	order := z.TokenOrderV2{
		Sender:      []byte(rlm.Address().String()),
		Receiver:    receiver,
		BaseToken:   []byte(baseToken),
		BaseAmount:  baseAmount,
		QuoteToken:  cfg.QuoteToken,
		QuoteAmount: quoteAmount,
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
		Metadata:    cfg.Metadata,
	}

	operand, err := z.EncodeTokenOrderV2(order)
	if err != nil {
		return makeError(errEncodeTokenOrder, err.Error())
	}

	instruction := z.Instruction{
		Version: z.INSTR_VERSION_2,
		Opcode:  z.OP_TOKEN_ORDER,
		Operand: operand,
	}

	salt := deriveForwardSalt(sourceClient, sequence)
	timeoutTimestamp := forwardTimeoutTimestamp(memo.Timeout)

	// Intentionally not recovered: a panic here (e.g. zkgm.Send after it has
	// already escrowed the voucher) must revert this whole tx, so AtomOne's
	// own packet timeout can refund the original sender instead.
	pkt := zkgm.Send(cross(rlm), cfg.ZkgmChannelId, timeoutTimestamp, salt, instruction)

	// Lets ResolveForward(packetHash) find the original packet once
	// zkgm.GetSendResult reports this send's result. See store.go.
	packetHash := types.MustCommit(types.CommitPacket(pkt)).String()
	i.store.SetPendingForward(0, rlm, packetHash, adapter.NewPendingForward(sourceClient, sequence))

	// Defers this ICS20 packet's own ack until ResolveForward later confirms
	// the ZKGM send's outcome (see WriteHookAck) — not a real failure.
	return transfer.ErrHookAsync
}

// deriveForwardSalt derives a per-packet-unique ZKGM send salt from
// (sourceClient, sequence) — already unique per source client by core, so no
// extra counter state is needed.
func deriveForwardSalt(sourceClient string, sequence uint64) [32]byte {
	var seqBytes [8]byte
	binary.BigEndian.PutUint64(seqBytes[:], sequence)

	preimage := append([]byte(sourceClient), seqBytes[:]...)
	return sha256.Sum256(preimage)
}

// forwardTimeoutTimestamp returns an absolute nanosecond timeout for the
// outbound ZKGM packet, computed from the memo's optional duration string
// (e.g. "10m") relative to the current block time. Falls back to
// defaultForwardTimeout when raw is empty or unparseable.
func forwardTimeoutTimestamp(raw string) types.Timestamp {
	d := defaultForwardTimeout
	if raw != "" {
		if parsed, err := time.ParseDuration(raw); err == nil {
			d = parsed
		}
	}
	return types.Timestamp(uint64(time.Now().Add(d).UnixNano()))
}

// parseHexBytes decodes a hex string, accepting an optional "0x"/"0X" prefix.
func parseHexBytes(s string) ([]byte, error) {
	if len(s) >= 2 && s[0] == '0' && (s[1] == 'x' || s[1] == 'X') {
		s = s[2:]
	}
	return hex.DecodeString(s)
}
