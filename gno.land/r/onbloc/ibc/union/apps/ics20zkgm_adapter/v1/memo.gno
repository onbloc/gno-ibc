package ics20zkgm_adapter

import (
	"gno.land/p/onbloc/json"
)

// ForwardMemo mirrors the full PFM (Packet Forward Middleware) {"forward":
// {...}} shape used elsewhere in the Cosmos ecosystem verbatim, so AtomOne-
// side tooling that already knows how to build PFM memos can reuse that
// without learning a bespoke schema.
//
// Only Receiver and Timeout are read today (see v1/impl.gno's
// OnTransferRecv): the destination ZKGM channel comes from the denom
// registry (../store.gno's DenomConfig), not the memo, so Port/Channel have
// no use yet, and multi-hop retry-on-timeout is out of scope for now (see
// issue #134). They're still parsed and kept on the struct so the full
// schema stays visible in one place, and so using them later is just a
// field access at the call site, not a parser change.
type ForwardMemo struct {
	Receiver string
	Port     string
	Channel  string
	Timeout  string // duration string (e.g. "10m")
	Retries  int
}

// parseForwardMemo returns (memo, true) for a valid {"forward": {"receiver":
// "..."}} payload. It returns (zero, false) for anything else — an empty
// memo, malformed JSON, a memo meant for something other than forwarding, or
// a forward object missing/blank receiver. Callers treat false as "this
// transfer is not a forward request", not as an error: not every ICS20
// transfer through this hook is meant to be forwarded. Every field besides
// Receiver is best-effort: absent or malformed leaves it at its zero value
// rather than failing the whole parse.
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

	receiverNode, err := fwd.GetKey("receiver")
	if err != nil {
		return ForwardMemo{}, false
	}

	receiver, err := receiverNode.GetString()
	if err != nil || receiver == "" {
		return ForwardMemo{}, false
	}

	memo := ForwardMemo{Receiver: receiver}

	if n, err := fwd.GetKey("port"); err == nil {
		if v, err := n.GetString(); err == nil {
			memo.Port = v
		}
	}
	if n, err := fwd.GetKey("channel"); err == nil {
		if v, err := n.GetString(); err == nil {
			memo.Channel = v
		}
	}
	if n, err := fwd.GetKey("timeout"); err == nil {
		if v, err := n.GetString(); err == nil {
			memo.Timeout = v
		}
	}
	if n, err := fwd.GetKey("retries"); err == nil {
		if v, err := n.GetNumeric(); err == nil {
			memo.Retries = int(v)
		}
	}

	return memo, true
}
