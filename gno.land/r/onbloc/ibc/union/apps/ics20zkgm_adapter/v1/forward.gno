package ics20zkgm_adapter

import (
	"crypto/sha256"
	"encoding/binary"
	"encoding/hex"
	"strconv"
	"time"

	u256 "gno.land/p/gnoswap/uint256"
	types "gno.land/p/onbloc/ibc/union/types"
	z "gno.land/p/onbloc/ibc/union/zkgm"
	"gno.land/r/aib/ibc/apps/transfer"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
)

// defaultForwardTimeout is used when the memo omits (or has an unparseable)
// timeout duration. It only bounds the outbound ZKGM packet's own expiry;
// if it fires, the escrowed voucher refunds back to this adapter's own
// address via zkgm's normal refund path (see forward.go doc on OnTransferRecv
// in impl.gno), not to the original AtomOne sender.
const defaultForwardTimeout = 24 * time.Hour

// OnTransferRecv implements adapter.IImpl. Forward direction: AtomOne -> EVM.
// See the doc comment in impl.gno for the Kind=INITIALIZE rationale.
func (i *Impl) OnTransferRecv(_ int, rlm realm, sourceClient string, sequence uint64, data transfer.FungibleTokenPacketData, denom transfer.Denom) error {
	memo, ok := parseForwardMemo(data.Memo)
	if !ok {
		return nil
	}

	// Forwarding requires the mint to have landed on this adapter (the ICS20
	// receiver must be set to our own address; the real recipient lives in
	// memo.Receiver instead). Otherwise we'd approve/send against a voucher
	// balance we don't actually hold.
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

	order := z.TokenOrderV2{
		Sender:      []byte(rlm.Address().String()),
		Receiver:    receiver,
		BaseToken:   []byte(denom.HashHex()),
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

	// Intentionally not recovered: any panic here (e.g. from zkgm.Send after
	// it has already escrowed the voucher) must revert this whole tx so the
	// ICS20 recv never commits — see the OnTransferRecv/zkgm.Send discussion:
	// a caught-and-swallowed panic could leave the voucher escrowed with no
	// packet ever sent, whereas an uncommitted recv lets AtomOne's own
	// packet timeout refund the original sender.
	zkgm.Send(cross(rlm), cfg.ZkgmChannelId, timeoutTimestamp, salt, instruction)

	return nil
}

// deriveForwardSalt derives a per-packet-unique ZKGM send salt from the
// underlying IBC packet's (sourceClient, sequence). sequence is already
// guaranteed unique per source client by core, so this needs no counter of
// its own (see the design discussion: reusing an existing guarantee beats
// introducing new state we'd have to maintain correctly forever).
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
