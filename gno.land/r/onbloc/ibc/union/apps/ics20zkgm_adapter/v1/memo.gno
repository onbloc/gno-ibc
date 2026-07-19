package ics20zkgm_adapter

import (
	"gno.land/p/onbloc/json"
)

// ForwardMemo mirrors the Cosmos ecosystem's PFM {"forward": {...}} shape
// verbatim, so existing AtomOne-side tooling can reuse it as-is.
//
// Only Receiver and Timeout are read today; Port/Channel/Retries are parsed
// and kept but unused (channel comes from store.go's DenomConfig instead, and
// multi-hop retry is out of scope — see issue #134), so the full schema stays
// visible and using them later needs no parser change.
type ForwardMemo struct {
	Receiver string
	Port     string
	Channel  string
	Timeout  string // duration string (e.g. "10m")
	Retries  int
}

// parseForwardMemo returns (memo, true) for a valid {"forward": {"receiver":
// "..."}} payload, or (zero, false) for anything else (empty/malformed memo,
// non-forward memo, missing/blank receiver) — false just means "not a
// forward request", not an error. Fields besides Receiver are best-effort:
// absent or malformed leaves them at zero rather than failing the parse.
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
