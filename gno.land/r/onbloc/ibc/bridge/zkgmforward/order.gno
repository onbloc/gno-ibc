package zkgmforward

import (
	"crypto/sha256"
	"encoding/hex"
	"time"

	"gno.land/p/aib/encoding"
	u256 "gno.land/p/onbloc/math/uint256"
	unionTypes "gno.land/p/onbloc/ibc/union/types"
	z "gno.land/p/onbloc/ibc/union/zkgm"
)

// defaultForwardTimeout bounds the outbound ZKGM packet's own expiry when the
// memo omits a timeout. On timeout the escrowed voucher refunds to this realm's
// address, and the deferred parent ack is resolved as an error (refunding the
// original AtomOne sender) via transfer.CompleteForwardAck.
const defaultForwardTimeout = 24 * time.Hour

// buildTokenOrder encodes the ZKGM TokenOrderV2 instruction for a forward.
// sender is this realm's address (which holds the escrowed voucher);
// baseTokenKey is the voucher's grc20reg key.
func buildTokenOrder(sender, baseTokenKey string, amount int64, fwd ForwardMemo) z.Instruction {
	metadata, err := z.EncodeTokenMetadata(z.TokenMetadata{
		Implementation: fwd.Metadata.Implementation,
		Initializer:    fwd.Metadata.Initializer,
	})
	if err != nil {
		panic("zkgmforward: encode metadata: " + err.Error())
	}

	amountU256 := u256.NewUintFromInt64(amount)
	operand, err := z.EncodeTokenOrderV2(z.TokenOrderV2{
		Sender:      []byte(sender),
		Receiver:    fwd.Receiver,
		BaseToken:   []byte(baseTokenKey),
		BaseAmount:  amountU256,
		QuoteToken:  fwd.QuoteToken,
		QuoteAmount: amountU256,
		Kind:        fwd.Kind,
		Metadata:    metadata,
	})
	if err != nil {
		panic("zkgmforward: encode token order: " + err.Error())
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
