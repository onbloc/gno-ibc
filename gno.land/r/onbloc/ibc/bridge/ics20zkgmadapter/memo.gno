package ics20zkgmadapter

import (
	"encoding/hex"

	"gno.land/p/nt/ufmt/v0"
	"gno.land/p/onbloc/json"
)

// ForwardMemo mirrors standard PFM's {"forward": {receiver, port, channel,
// timeout, retries}} memo, shared by both legs. Port/Retries are unused.
// QuoteToken/Metadata are a zkgm-only extension (no PFM equivalent, required
// for a TokenOrderV2 mint) - their presence is how parseZkgmMemo/
// parseICS20Memo tell the two directions apart. Memo is likewise ics20-only.
type ForwardMemo struct {
	Receiver string
	Port     string
	Channel  string
	Timeout  uint64
	Retries  uint64

	QuoteToken []byte
	Metadata   ForwardMemoMetadata

	Memo string
}

type ForwardMemoMetadata struct {
	Implementation []byte
	Initializer    []byte
}

// forwardObject parses raw and returns its "forward" object.
func forwardObject(raw string) (*json.Node, error) {
	if raw == "" {
		return nil, ufmt.Errorf("forward memo: empty")
	}

	root, err := json.Unmarshal([]byte(raw))
	if err != nil {
		return nil, ufmt.Errorf("forward memo: invalid json: %v", err)
	}

	fwd, err := root.GetKey("forward")
	if err != nil {
		return nil, ufmt.Errorf("forward memo: missing \"forward\" object")
	}

	return fwd, nil
}

// parseZkgmMemo parses the AtomOne->Gno->Union leg (forwardZkgmHandler),
// requiring "quote_token" to catch a wrong-direction memo early.
func parseZkgmMemo(raw string) (ForwardMemo, error) {
	fwd, err := forwardObject(raw)
	if err != nil {
		return ForwardMemo{}, err
	}

	if _, err := fwd.GetKey("quote_token"); err != nil {
		return ForwardMemo{}, ufmt.Errorf("forward memo: missing \"quote_token\" (wrong direction?)")
	}

	return parseZkgmForwardMemo(fwd)
}

// parseICS20Memo parses the Union->Gno->AtomOne leg (forwardIcs20Handler),
// rejecting a "quote_token" (the other leg's field).
func parseICS20Memo(raw string) (ForwardMemo, error) {
	fwd, err := forwardObject(raw)
	if err != nil {
		return ForwardMemo{}, err
	}

	if _, err := fwd.GetKey("quote_token"); err == nil {
		return ForwardMemo{}, ufmt.Errorf("forward memo: unexpected \"quote_token\" (wrong direction?)")
	}

	return parseICS20ForwardMemo(fwd)
}

// parsePFMCore reads the fields common to both legs. Receiver/Channel are
// required; Port/Timeout/Retries are optional and unused.
func parsePFMCore(fwd *json.Node) (receiver, port, channel string, timeout, retries uint64, err error) {
	receiver, err = memoString(fwd, "receiver")
	if err != nil {
		return "", "", "", 0, 0, err
	}

	channel, err = memoString(fwd, "channel")
	if err != nil {
		return "", "", "", 0, 0, err
	}

	if portNode, perr := fwd.GetKey("port"); perr == nil {
		port, _ = portNode.GetString()
	}

	if timeoutNode, terr := fwd.GetKey("timeout"); terr == nil {
		if timeoutNum, nerr := timeoutNode.GetNumeric(); nerr == nil {
			timeout = uint64(timeoutNum)
		}
	}

	if retriesNode, rerr := fwd.GetKey("retries"); rerr == nil {
		if retriesNum, nerr := retriesNode.GetNumeric(); nerr == nil {
			retries = uint64(retriesNum)
		}
	}

	return receiver, port, channel, timeout, retries, nil
}

// parseZkgmForwardMemo decodes the zkgm leg: shared PFM fields plus
// quote_token/metadata. receiver is validated as hex and normalized here.
func parseZkgmForwardMemo(fwd *json.Node) (ForwardMemo, error) {
	receiver, port, channel, timeout, retries, err := parsePFMCore(fwd)
	if err != nil {
		return ForwardMemo{}, err
	}

	receiverBytes, err := decodeHex(receiver)
	if err != nil {
		return ForwardMemo{}, ufmt.Errorf("forward memo: \"receiver\" is not valid hex: %v", err)
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

	return ForwardMemo{
		Receiver: hex.EncodeToString(receiverBytes),
		Port:     port,
		Channel:  channel,
		Timeout:  timeout,
		Retries:  retries,
		QuoteToken: quoteToken,
		Metadata: ForwardMemoMetadata{
			Implementation: implementation,
			Initializer:    initializer,
		},
	}, nil
}

// parseICS20ForwardMemo decodes the ics20 leg: shared PFM fields plus the
// passthrough memo.
func parseICS20ForwardMemo(fwd *json.Node) (ForwardMemo, error) {
	receiver, port, channel, timeout, retries, err := parsePFMCore(fwd)
	if err != nil {
		return ForwardMemo{}, err
	}

	memo := ForwardMemo{
		Receiver: receiver,
		Port:     port,
		Channel:  channel,
		Timeout:  timeout,
		Retries:  retries,
	}

	if memoNode, err := fwd.GetKey("memo"); err == nil {
		if s, err := memoNode.GetString(); err == nil {
			memo.Memo = s
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
