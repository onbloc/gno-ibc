package ics20zkgmadapter

import (
	"encoding/hex"

	"gno.land/p/nt/ufmt/v0"
	"gno.land/p/onbloc/json"
)

// ForwardMemo is a PFM-style {"forward": {...}} memo shared by both
// forwarding legs ics20zkgmadapter implements: Channel/Receiver/QuoteToken/
// Metadata for AtomOne->Gno->Union (order.gno), DestinationClient/
// AtomoneReceiver/Memo for Union->Gno->AtomOne (forwardics20.gno). Only the
// fields for the sender's direction need to be present.
type ForwardMemo struct {
	Channel    uint32
	Receiver   []byte
	QuoteToken []byte
	Metadata   ForwardMemoMetadata

	DestinationClient string
	AtomoneReceiver   string
	Memo              string

	TimeoutTimestamp uint64
}

type ForwardMemoMetadata struct {
	Implementation []byte
	Initializer    []byte
}

// parseForwardMemo parses a forward memo, picking the branch based on
// whether "destination_client" is set.
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

	if _, err := fwd.GetKey("destination_client"); err == nil {
		return parseICS20ForwardMemo(fwd)
	}

	return parseZkgmForwardMemo(fwd)
}

// parseZkgmForwardMemo decodes the AtomOne->Gno->Union leg's fields.
func parseZkgmForwardMemo(fwd *json.Node) (ForwardMemo, error) {
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
	}

	if timeoutNode, err := fwd.GetKey("timeout_timestamp"); err == nil {
		if timeoutNum, err := timeoutNode.GetNumeric(); err == nil {
			memo.TimeoutTimestamp = uint64(timeoutNum)
		}
	}

	return memo, nil
}

// parseICS20ForwardMemo decodes the Union->Gno->AtomOne leg's fields.
func parseICS20ForwardMemo(fwd *json.Node) (ForwardMemo, error) {
	destinationClient, err := memoString(fwd, "destination_client")
	if err != nil {
		return ForwardMemo{}, err
	}
	atomoneReceiver, err := memoString(fwd, "atomone_receiver")
	if err != nil {
		return ForwardMemo{}, err
	}

	memo := ForwardMemo{
		DestinationClient: destinationClient,
		AtomoneReceiver:   atomoneReceiver,
	}

	if memoNode, err := fwd.GetKey("memo"); err == nil {
		if s, err := memoNode.GetString(); err == nil {
			memo.Memo = s
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

// memoString reads a required, non-empty plain string field off node.
func memoString(node *json.Node, key string) (string, error) {
	child, err := node.GetKey(key)
	if err != nil {
		return "", ufmt.Errorf("forward memo: missing %q", key)
	}

	value, err := child.GetString()
	if err != nil {
		return "", ufmt.Errorf("forward memo: %q must be a string", key)
	}
	if value == "" {
		return "", ufmt.Errorf("forward memo: %q must not be empty", key)
	}

	return value, nil
}

// decodeHex decodes a hex string, accepting an optional 0x/0X prefix.
func decodeHex(s string) ([]byte, error) {
	if len(s) >= 2 && s[0] == '0' && (s[1] == 'x' || s[1] == 'X') {
		s = s[2:]
	}
	return hex.DecodeString(s)
}
