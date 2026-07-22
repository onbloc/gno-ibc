package transfer

import (
	"gno.land/p/onbloc/ibc/union/zkgm"
	"gno.land/p/onbloc/json"
)

// ForwardMemo is a PFM-style {"forward": {...}} memo. It also carries the
// ZKGM TokenOrderV2 fields (QuoteToken, Metadata) that would otherwise need
// an off-chain EVM view call to compute, since this realm can't make that
// call itself — whoever builds the tx is expected to have resolved them.
type ForwardMemo struct {
	Channel          uint32
	Receiver         string
	QuoteToken       string
	Metadata         ForwardMemoMetadata
	Kind             uint8
	TimeoutTimestamp uint64
}

type ForwardMemoMetadata struct {
	Implementation string
	Initializer    string
}

// parseForwardMemo returns (memo, true) for a valid forward memo, or
// (zero, false) otherwise — false just means "not a forward", not an error.
func parseForwardMemo(raw string) (ForwardMemo, bool) {
	if raw == "" {
		return ForwardMemo{}, false
	}

	root, err := json.Unmarshal([]byte(raw))
	if err != nil {
		return ForwardMemo{}, false
	}

	fwd, err := root.GetKey("forward")
	if err != nil {
		return ForwardMemo{}, false
	}

	receiver, ok := memoString(fwd, "receiver")
	if !ok {
		return ForwardMemo{}, false
	}

	channelNode, err := fwd.GetKey("channel")
	if err != nil {
		return ForwardMemo{}, false
	}
	channelNum, err := channelNode.GetNumeric()
	if err != nil {
		return ForwardMemo{}, false
	}

	quoteToken, ok := memoString(fwd, "quote_token")
	if !ok {
		return ForwardMemo{}, false
	}

	metadataNode, err := fwd.GetKey("metadata")
	if err != nil {
		return ForwardMemo{}, false
	}

	implementation, ok := memoString(metadataNode, "implementation")
	if !ok {
		return ForwardMemo{}, false
	}

	initializer, ok := memoString(metadataNode, "initializer")
	if !ok {
		return ForwardMemo{}, false
	}

	memo := ForwardMemo{
		Channel:    uint32(channelNum),
		Receiver:   receiver,
		QuoteToken: quoteToken,
		Metadata: ForwardMemoMetadata{
			Implementation: implementation,
			Initializer:    initializer,
		},
		Kind: zkgm.TOKEN_ORDER_KIND_INITIALIZE,
	}

	if kindNode, err := fwd.GetKey("kind"); err == nil {
		if kindNum, err := kindNode.GetNumeric(); err == nil {
			memo.Kind = uint8(kindNum)
		}
	}

	if timeoutNode, err := fwd.GetKey("timeout_timestamp"); err == nil {
		if timeoutNum, err := timeoutNode.GetNumeric(); err == nil {
			memo.TimeoutTimestamp = uint64(timeoutNum)
		}
	}

	return memo, true
}

// memoString reads a required non-empty string field off of node.
func memoString(node *json.Node, key string) (string, bool) {
	child, err := node.GetKey(key)
	if err != nil {
		return "", false
	}

	value, err := child.GetString()
	if err != nil || value == "" {
		return "", false
	}

	return value, true
}
