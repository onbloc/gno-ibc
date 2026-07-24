package zkgmforward

import (
	"encoding/hex"

	z "gno.land/p/onbloc/ibc/union/zkgm"
	"gno.land/p/nt/ufmt/v0"
	"gno.land/p/onbloc/json"
)

// ForwardMemo is a PFM-style {"forward": {...}} memo. It also carries the ZKGM
// TokenOrderV2 fields (QuoteToken, Metadata) that would otherwise need an
// off-chain EVM view call to compute, since this realm can't make that call
// itself — whoever builds the tx is expected to have resolved them.
//
// Receiver/QuoteToken/Metadata are decoded from their hex JSON representation
// at parse time, so downstream code works with the raw bytes directly.
type ForwardMemo struct {
	Channel          uint32
	Receiver         []byte
	QuoteToken       []byte
	Metadata         ForwardMemoMetadata
	Kind             uint8
	TimeoutTimestamp uint64
}

type ForwardMemoMetadata struct {
	Implementation []byte
	Initializer    []byte
}

// parseForwardMemo parses and validates a forward memo, decoding its hex fields.
// It returns a descriptive error (nil on success) so callers can surface the
// specific reason a forward was rejected.
func parseForwardMemo(raw string) (ForwardMemo, error) {
	if raw == "" {
		return ForwardMemo{}, ufmt.Errorf("forward memo: empty")
	}

	root, err := json.Unmarshal([]byte(raw))
	if err != nil {
		return ForwardMemo{}, ufmt.Errorf("forward memo: invalid json: %v", err)
	}

	fwd, err := root.GetKey("forward")
	if err != nil {
		return ForwardMemo{}, ufmt.Errorf("forward memo: missing \"forward\" object")
	}

	receiver, err := memoHex(fwd, "receiver")
	if err != nil {
		return ForwardMemo{}, err
	}

	channelNode, err := fwd.GetKey("channel")
	if err != nil {
		return ForwardMemo{}, ufmt.Errorf("forward memo: missing \"channel\"")
	}
	channelNum, err := channelNode.GetNumeric()
	if err != nil {
		return ForwardMemo{}, ufmt.Errorf("forward memo: \"channel\" must be numeric: %v", err)
	}

	quoteToken, err := memoHex(fwd, "quote_token")
	if err != nil {
		return ForwardMemo{}, err
	}

	metadataNode, err := fwd.GetKey("metadata")
	if err != nil {
		return ForwardMemo{}, ufmt.Errorf("forward memo: missing \"metadata\"")
	}
	implementation, err := memoHex(metadataNode, "implementation")
	if err != nil {
		return ForwardMemo{}, err
	}
	initializer, err := memoHex(metadataNode, "initializer")
	if err != nil {
		return ForwardMemo{}, err
	}

	memo := ForwardMemo{
		Channel:    uint32(channelNum),
		Receiver:   receiver,
		QuoteToken: quoteToken,
		Metadata: ForwardMemoMetadata{
			Implementation: implementation,
			Initializer:    initializer,
		},
		Kind: z.TOKEN_ORDER_KIND_INITIALIZE,
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

	return memo, nil
}

// memoHex reads a required, non-empty, hex-encoded string field off node and
// decodes it to bytes (accepting an optional 0x prefix).
func memoHex(node *json.Node, key string) ([]byte, error) {
	child, err := node.GetKey(key)
	if err != nil {
		return nil, ufmt.Errorf("forward memo: missing %q", key)
	}

	value, err := child.GetString()
	if err != nil {
		return nil, ufmt.Errorf("forward memo: %q must be a string", key)
	}
	if value == "" {
		return nil, ufmt.Errorf("forward memo: %q must not be empty", key)
	}

	bz, err := decodeHex(value)
	if err != nil {
		return nil, ufmt.Errorf("forward memo: %q is not valid hex: %v", key, err)
	}
	return bz, nil
}

// decodeHex decodes a hex string, accepting an optional 0x/0X prefix.
func decodeHex(s string) ([]byte, error) {
	if len(s) >= 2 && s[0] == '0' && (s[1] == 'x' || s[1] == 'X') {
		s = s[2:]
	}
	return hex.DecodeString(s)
}
