package ucs03_zkgm

import (
	u256 "gno.land/p/gnoswap/uint256"
	types "gno.land/p/onbloc/ibc/union/types"
	tb "gno.land/p/onbloc/ibc/union/zkgm/tokenbucket"
)

// GetTokenBucket returns a snapshot of the rate-limit bucket configured for denom.
func GetTokenBucket(denom string) (*tb.TokenBucket, error) {
	return mustGetImpl().GetTokenBucket(denom)
}

// GetChannelBalanceV2 returns the escrow balance for the v2 channel-balance key.
func GetChannelBalanceV2(channelId types.ChannelId, path *u256.Uint, baseToken string, quoteToken []byte) (*u256.Uint, error) {
	return mustGetImpl().GetChannelBalanceV2(channelId, path, baseToken, quoteToken)
}

// GetSendResult returns the recorded ack/timeout result for a packet
// previously returned by Send, keyed by its commitment hash
// (types.MustCommit(types.CommitPacket(pkt))).
func GetSendResult(packetHash string) (successful bool, ack []byte, resolved bool, found bool) {
	return mustGetImpl().GetSendResult(packetHash)
}
