package transfer

import (
	"crypto/sha256"
	"encoding/hex"
	"time"

	"gno.land/p/aib/encoding"
	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/fqname/v0"
	unionTypes "gno.land/p/onbloc/ibc/union/types"
	z "gno.land/p/onbloc/ibc/union/zkgm"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
)

// defaultForwardTimeout bounds the outbound ZKGM packet's own expiry when the
// memo omits a timeout. On timeout the escrowed voucher refunds to this
// realm's own address, not the original AtomOne sender.
const defaultForwardTimeout = 24 * time.Hour

// tryForward forwards onward via ZKGM when data.Receiver is zkgm's proxy
// address (a fixed realm address, not relayer-custodied); the memo only
// carries routing data. Returns false for any other receiver. Once receiver
// signals forward intent, a malformed memo is a hard failure, not a
// fallback mint to zkgm's own proxy address.
func tryForward(cur realm, sourceClient, destinationClient, icsReceiver string, sequence uint64, memo, voucherDenom string, amount int64) bool {
	if address(icsReceiver) != zkgm.ProxyAddress() {
		return false
	}

	fwd, ok := parseForwardMemo(memo)
	if !ok {
		panic("transfer: forward: receiver is zkgm's proxy address but memo is not a valid forward instruction")
	}

	inst := getVoucher(voucherDenom)
	if inst == nil {
		panic("transfer: forward: voucher not found for " + voucherDenom)
	}
	if err := inst.ledger.Mint(cur.Address(), amount); err != nil {
		panic("transfer: forward: mint error: " + err.Error())
	}

	// zkgm's escrow pulls via TransferFrom, so it needs an allowance.
	teller := inst.ledger.ImpersonateTeller(cur.Address())
	if err := teller.Approve(0, cur, zkgm.ProxyAddress(), amount); err != nil {
		panic("transfer: forward: approve error: " + err.Error())
	}

	receiver := mustDecodeHex("receiver", fwd.Receiver)
	quoteToken := mustDecodeHex("quote_token", fwd.QuoteToken)
	metadata, err := z.EncodeTokenMetadata(z.TokenMetadata{
		Implementation: mustDecodeHex("metadata.implementation", fwd.Metadata.Implementation),
		Initializer:    mustDecodeHex("metadata.initializer", fwd.Metadata.Initializer),
	})
	if err != nil {
		panic("transfer: forward: encode metadata: " + err.Error())
	}

	// grc20reg keys by rlmPath.symbol, not the full IBC hash.
	baseToken := fqname.Construct(cur.PkgPath(), VoucherSymbol(voucherDenom))
	amountU256 := u256.NewUintFromInt64(amount)

	operand, err := z.EncodeTokenOrderV2(z.TokenOrderV2{
		Sender:      []byte(cur.Address().String()),
		Receiver:    receiver,
		BaseToken:   []byte(baseToken),
		BaseAmount:  amountU256,
		QuoteToken:  quoteToken,
		QuoteAmount: amountU256,
		Kind:        fwd.Kind,
		Metadata:    metadata,
	})
	if err != nil {
		panic("transfer: forward: encode token order: " + err.Error())
	}

	instruction := z.Instruction{
		Version: z.INSTR_VERSION_2,
		Opcode:  z.OP_TOKEN_ORDER,
		Operand: operand,
	}

	corrID := forwardCorrID(sourceClient, sequence)
	salt := deriveForwardSalt(sourceClient, sequence)
	timeout := forwardTimeoutTimestamp(fwd.TimeoutTimestamp)

	// Not recovered: a panic here must revert this whole tx (including the
	// mint above) so the AtomOne packet can be resubmitted.
	zkgm.SendWithCallback(cross(cur), unionTypes.ChannelId(fwd.Channel), timeout, salt, instruction, corrID)

	setPendingForward(corrID, pendingForward{
		DestinationClient: destinationClient,
		Sequence:          sequence,
		VoucherDenom:      voucherDenom,
		Amount:            amount,
	})

	return true
}

// deriveForwardSalt derives a per-packet-unique ZKGM send salt from
// (sourceClient, sequence) - already unique per source client via core, so
// no extra counter state is needed.
func deriveForwardSalt(sourceClient string, sequence uint64) [32]byte {
	preimage := append([]byte(sourceClient), encoding.Uint64ToBigEndian(sequence)...)
	return sha256.Sum256(preimage)
}

// forwardTimeoutTimestamp returns memoTimeout if set, else an absolute
// nanosecond timeout defaultForwardTimeout from now.
func forwardTimeoutTimestamp(memoTimeout uint64) unionTypes.Timestamp {
	if memoTimeout != 0 {
		return unionTypes.Timestamp(memoTimeout)
	}
	return unionTypes.Timestamp(uint64(time.Now().Add(defaultForwardTimeout).UnixNano()))
}

func mustDecodeHex(field, s string) []byte {
	if len(s) >= 2 && s[0] == '0' && (s[1] == 'x' || s[1] == 'X') {
		s = s[2:]
	}
	bz, err := hex.DecodeString(s)
	if err != nil {
		panic("transfer: forward: invalid " + field + " hex: " + err.Error())
	}
	return bz
}
