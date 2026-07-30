package ics20zkgmadapter

import (
	"encoding/hex"
	"strconv"
	"time"

	"gno.land/p/nt/ufmt/v0"
	"gno.land/p/onbloc/json"
	ics20 "gno.land/r/aib/ibc/apps/transfer"
)

// PFMCore holds real PFM's {receiver, port, channel, timeout, retries}
// fields, common to both legs. Optional fields, when present, must have the
// right type/value or the whole memo is rejected (fail closed) instead of
// silently defaulting - a malformed memo must fail in Prepare, before any
// custody is taken.
type PFMCore struct {
	Receiver string
	Port     string
	Channel  string
	Timeout  uint64 // absolute UnixNano deadline; 0 if the memo omitted it
}

// ZkgmForwardMemo is the AtomOne->Gno->Union leg's parsed memo (order.gno).
// QuoteToken/Metadata are a zkgm-only extension PFM has no equivalent for,
// required for a TokenOrderV2 mint; their presence in the raw memo is how
// parseZkgmMemo/parseICS20Memo tell the two directions apart.
type ZkgmForwardMemo struct {
	Core PFMCore
	// ChannelID is Core.Channel, pre-parsed as a Union channel id: validated
	// numeric here, so consumers never re-parse (or re-guard a parse that
	// "cannot fail").
	ChannelID  uint32
	QuoteToken []byte
	Metadata   ForwardMemoMetadata
}

// ICS20ForwardMemo is the Union->Gno->AtomOne leg's parsed memo
// (forwardics20.gno). Next is PFM's passthrough memo for the onward ICS20
// transfer.
type ICS20ForwardMemo struct {
	Core PFMCore
	Next string
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
func parseZkgmMemo(raw string) (ZkgmForwardMemo, error) {
	fwd, err := forwardObject(raw)
	if err != nil {
		return ZkgmForwardMemo{}, err
	}

	if _, err := fwd.GetKey("quote_token"); err != nil {
		return ZkgmForwardMemo{}, ufmt.Errorf("forward memo: missing \"quote_token\" (wrong direction?)")
	}

	return parseZkgmForwardMemo(fwd)
}

// parseICS20Memo parses the Union->Gno->AtomOne leg (forwardIcs20Handler),
// rejecting a "quote_token" (the other leg's field).
func parseICS20Memo(raw string) (ICS20ForwardMemo, error) {
	fwd, err := forwardObject(raw)
	if err != nil {
		return ICS20ForwardMemo{}, err
	}

	if _, err := fwd.GetKey("quote_token"); err == nil {
		return ICS20ForwardMemo{}, ufmt.Errorf("forward memo: unexpected \"quote_token\" (wrong direction?)")
	}

	return parseICS20ForwardMemo(fwd)
}

// parsePFMCore reads real PFM's shared fields. Receiver/Channel are
// required. Port/Timeout/Retries are optional, but a present field with the
// wrong type is rejected rather than silently defaulted.
func parsePFMCore(fwd *json.Node) (PFMCore, error) {
	receiver, err := memoString(fwd, "receiver")
	if err != nil {
		return PFMCore{}, err
	}

	channel, err := memoString(fwd, "channel")
	if err != nil {
		return PFMCore{}, err
	}

	port, err := optionalString(fwd, "port")
	if err != nil {
		return PFMCore{}, err
	}

	timeout, err := optionalTimeout(fwd)
	if err != nil {
		return PFMCore{}, err
	}

	if err := rejectUnsupportedRetries(fwd); err != nil {
		return PFMCore{}, err
	}

	return PFMCore{Receiver: receiver, Port: port, Channel: channel, Timeout: timeout}, nil
}

// rejectUnsupportedRetries errors if "retries" is present and non-zero:
// neither leg implements retry-on-timeout, so silently accepting a nonzero
// value would promise a retry that never happens. Not stored on PFMCore -
// the only valid value is 0/absent, so there's nothing worth keeping.
func rejectUnsupportedRetries(fwd *json.Node) error {
	retries, err := optionalUint(fwd, "retries")
	if err != nil {
		return err
	}
	if retries > 0 {
		return ufmt.Errorf("forward memo: \"retries\" is not supported (retry-on-timeout is not implemented)")
	}
	return nil
}

// parseZkgmForwardMemo decodes the zkgm leg: shared PFM fields (channel must
// be a numeric Union channel id - this leg has no "channel-N" convention)
// plus quote_token/metadata. receiver/channel are validated here so a
// malformed value fails before any custody is taken.
func parseZkgmForwardMemo(fwd *json.Node) (ZkgmForwardMemo, error) {
	core, err := parsePFMCore(fwd)
	if err != nil {
		return ZkgmForwardMemo{}, err
	}

	if core.Port != "" {
		return ZkgmForwardMemo{}, ufmt.Errorf("forward memo: \"port\" is not valid for this leg")
	}

	channelID, err := strconv.ParseUint(core.Channel, 10, 32)
	if err != nil {
		return ZkgmForwardMemo{}, ufmt.Errorf("forward memo: \"channel\" must be a numeric Union channel id: %v", err)
	}

	receiverBytes, err := decodeHex(core.Receiver)
	if err != nil {
		return ZkgmForwardMemo{}, ufmt.Errorf("forward memo: \"receiver\" is not valid hex: %v", err)
	}
	core.Receiver = hex.EncodeToString(receiverBytes)

	quoteToken, err := memoHex(fwd, "quote_token")
	if err != nil {
		return ZkgmForwardMemo{}, err
	}

	metadataNode, err := fwd.GetKey("metadata")
	if err != nil {
		return ZkgmForwardMemo{}, ufmt.Errorf("forward memo: missing \"metadata\"")
	}
	implementation, err := memoHex(metadataNode, "implementation")
	if err != nil {
		return ZkgmForwardMemo{}, err
	}
	initializer, err := memoHex(metadataNode, "initializer")
	if err != nil {
		return ZkgmForwardMemo{}, err
	}

	return ZkgmForwardMemo{
		Core:       core,
		ChannelID:  uint32(channelID),
		QuoteToken: quoteToken,
		Metadata: ForwardMemoMetadata{
			Implementation: implementation,
			Initializer:    initializer,
		},
	}, nil
}

// parseICS20ForwardMemo decodes the ics20 leg: shared PFM fields plus PFM's
// "next" passthrough memo. port, if present, must be the fixed transfer
// port - the only one this leg ever sends through.
func parseICS20ForwardMemo(fwd *json.Node) (ICS20ForwardMemo, error) {
	core, err := parsePFMCore(fwd)
	if err != nil {
		return ICS20ForwardMemo{}, err
	}

	if core.Port != "" && core.Port != ics20.PortID {
		return ICS20ForwardMemo{}, ufmt.Errorf("forward memo: \"port\" must be %q, got %q", ics20.PortID, core.Port)
	}

	if err := checkIcs20TimeoutBounds(core.Timeout); err != nil {
		return ICS20ForwardMemo{}, err
	}

	next, err := nextMemo(fwd)
	if err != nil {
		return ICS20ForwardMemo{}, err
	}

	return ICS20ForwardMemo{Core: core, Next: next}, nil
}

// icsMinForwardTimeout guards against a memo timeout so close to "now" that
// truncating it down to whole seconds for aib's TimeoutTimestamp (see
// forwardIcs20TimeoutTimestamp) could land on the current second, tripping
// aib core's "timeout must be after now" check at Execute time instead of
// failing cleanly here in Prepare.
const icsMinForwardTimeout = 2 * time.Second

// checkIcs20TimeoutBounds rejects a resolved timeout (0 = memo omitted it,
// always fine) outside aib core SendPacket's actual [now, now+24h) window,
// using the same margin forwardIcs20TimeoutTimestamp's own default already
// stays under. A permanent out-of-range input fails here, before any
// custody is taken, instead of panicking in Execute.
func checkIcs20TimeoutBounds(absoluteNano uint64) error {
	if absoluteNano == 0 {
		return nil
	}

	now := uint64(time.Now().UnixNano())
	if absoluteNano < now+uint64(icsMinForwardTimeout) {
		return ufmt.Errorf("forward memo: \"timeout\" must be at least %s from now", icsMinForwardTimeout)
	}
	if max := now + uint64(defaultForwardIcs20Timeout); absoluteNano > max {
		return ufmt.Errorf("forward memo: \"timeout\" must be within %s from now", defaultForwardIcs20Timeout)
	}
	return nil
}

// nextMemo reads PFM's "next" field, accepting either a pre-encoded string
// or a nested object (re-marshaled to its JSON string form) - real PFM
// implementations accept both shapes for the next hop's own memo.
func nextMemo(fwd *json.Node) (string, error) {
	child, err := fwd.GetKey("next")
	if err != nil {
		return "", nil
	}

	if child.IsString() {
		return child.GetString()
	}
	if !child.IsObject() {
		return "", ufmt.Errorf("forward memo: \"next\" must be a string or an object")
	}

	bz, err := json.Marshal(child)
	if err != nil {
		return "", ufmt.Errorf("forward memo: \"next\" is not valid: %v", err)
	}
	return string(bz), nil
}

// optionalString reads key as a string if present, rejecting any other
// type. Absent returns "".
func optionalString(node *json.Node, key string) (string, error) {
	child, err := node.GetKey(key)
	if err != nil {
		return "", nil
	}

	s, err := child.GetString()
	if err != nil {
		return "", ufmt.Errorf("forward memo: %q must be a string", key)
	}
	return s, nil
}

// optionalUint reads key as a non-negative integer if present, rejecting
// any other type, a negative value, or a non-integer (GetNumeric returns
// float64, so e.g. 1.5 would otherwise silently truncate to 1). Absent
// returns 0.
func optionalUint(node *json.Node, key string) (uint64, error) {
	child, err := node.GetKey(key)
	if err != nil {
		return 0, nil
	}

	n, err := child.GetNumeric()
	if err != nil {
		return 0, ufmt.Errorf("forward memo: %q must be numeric", key)
	}
	if n < 0 {
		return 0, ufmt.Errorf("forward memo: %q must not be negative", key)
	}
	u := uint64(n)
	if float64(u) != n {
		return 0, ufmt.Errorf("forward memo: %q must be an integer", key)
	}
	return u, nil
}

// optionalTimeout reads PFM's "timeout" duration string (e.g. "10m") if
// present, resolving it to an absolute UnixNano deadline. Absent returns 0;
// each leg's own ...TimeoutTimestamp helper substitutes its default then.
func optionalTimeout(node *json.Node) (uint64, error) {
	child, err := node.GetKey("timeout")
	if err != nil {
		return 0, nil
	}

	s, err := child.GetString()
	if err != nil {
		return 0, ufmt.Errorf("forward memo: \"timeout\" must be a duration string (e.g. \"10m\")")
	}

	dur, err := time.ParseDuration(s)
	if err != nil {
		return 0, ufmt.Errorf("forward memo: \"timeout\" is not a valid duration: %v", err)
	}
	if dur <= 0 {
		return 0, ufmt.Errorf("forward memo: \"timeout\" must be positive")
	}

	return uint64(time.Now().Add(dur).UnixNano()), nil
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
