package ics20zkgmadapter

import (
	"crypto/sha256"
	"encoding/hex"
	"time"

	"gno.land/p/aib/encoding"
	unionTypes "gno.land/p/onbloc/ibc/union/types"
	z "gno.land/p/onbloc/ibc/union/zkgm"
	u256 "gno.land/p/onbloc/math/uint256"
)

// defaultForwardTimeout bounds the outbound ZKGM packet's own expiry when the
// memo omits a timeout. On timeout the escrowed voucher refunds to this realm's
// address, and the deferred parent ack is resolved as an error (refunding the
// original AtomOne sender) via ics20.CompleteForwardAck.
const defaultForwardTimeout = 24 * time.Hour

// buildTokenOrder encodes the ZKGM TokenOrderV2 instruction for a forward.
// sender is this realm's address (which holds the escrowed voucher);
// baseTokenKey is the voucher's grc20reg key.
func buildTokenOrder(sender, baseTokenKey string, amount int64, fwd ZkgmForwardMemo) z.Instruction {
	// Already validated as hex at parse time; cannot fail here.
	receiver, err := hex.DecodeString(fwd.Core.Receiver)
	if err != nil {
		panic("ics20zkgmadapter: forward memo receiver is not valid hex: " + err.Error())
	}

	metadata, err := z.EncodeTokenMetadata(z.TokenMetadata{
		Implementation: fwd.Metadata.Implementation,
		Initializer:    fwd.Metadata.Initializer,
	})
	if err != nil {
		panic("ics20zkgmadapter: encode metadata: " + err.Error())
	}

	amountU256 := u256.NewUintFromInt64(amount)
	operand, err := z.EncodeTokenOrderV2(z.TokenOrderV2{
		Sender:      []byte(sender),
		Receiver:    receiver,
		BaseToken:   []byte(baseTokenKey),
		BaseAmount:  amountU256,
		QuoteToken:  fwd.QuoteToken,
		QuoteAmount: amountU256,
		// Always ESCROW: new-asset bootstrap (INITIALIZE) is an admin-only
		// manual step, never something a forward memo can trigger.
		Kind:     z.TOKEN_ORDER_KIND_ESCROW,
		Metadata: metadata,
	})
	if err != nil {
		panic("ics20zkgmadapter: encode token order: " + err.Error())
	}

	return z.Instruction{
		Version: z.INSTR_VERSION_2,
		Opcode:  z.OP_TOKEN_ORDER,
		Operand: operand,
	}
}

// forwardCorrID is the corrID passed to zkgm.SendWithCallback and echoed back to
// OnZkgmSendResult. Unique per (sourceClient, sequence).
func forwardCorrID(sourceClient string, sequence uint64) string {
	return sourceClient + "/" + hex.EncodeToString(encoding.Uint64ToBigEndian(sequence))
}

// deriveForwardSalt derives a per-packet-unique ZKGM send salt from
// (sourceClient, sequence) — already unique per source client via core.
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
