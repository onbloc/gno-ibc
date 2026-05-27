package cometbls

import (
	"bytes"
	"testing"
)

func TestEncodeMisbehaviour(t *testing.T) {
	m := Misbehaviour{
		HeaderA: Header{SignedHeader: LightHeader{Height: 1}},
		HeaderB: Header{SignedHeader: LightHeader{Height: 2}},
	}
	want := mustHex(
		"0a26" + "0a24" + "0801" + "2220" + bytes32hex(0x00) +
			"1226" + "0a24" + "0802" + "2220" + bytes32hex(0x00),
	)
	bytesEq(t, "EncodeMisbehaviour", EncodeMisbehaviour(m), want)
}

func TestDecodeMisbehaviour(t *testing.T) {
	t.Run("basic", func(t *testing.T) {
		buf := []byte{
			0x0A, 0x04, 0x0A, 0x02, 0x08, 0x01,
			0x12, 0x04, 0x0A, 0x02, 0x08, 0x02,
		}
		got, err := DecodeMisbehaviour(buf)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if got.HeaderA.SignedHeader.Height != 1 {
			t.Fatalf("HeaderA.Height: got %d want 1", got.HeaderA.SignedHeader.Height)
		}
		if got.HeaderB.SignedHeader.Height != 2 {
			t.Fatalf("HeaderB.Height: got %d want 2", got.HeaderB.SignedHeader.Height)
		}
	})

	t.Run("timenanos_out_of_range", func(t *testing.T) {
		var tsBuf []byte
		tsBuf = pbAppendInt64(tsBuf, 1, 1000)
		tsBuf = pbAppendUint64(tsBuf, 2, 1_000_000_000)

		var lhBuf []byte
		lhBuf = pbAppendInt64(lhBuf, 1, 1)
		lhBuf = pbAppendMsg(lhBuf, 2, tsBuf)
		lhBuf = pbAppendBytes(lhBuf, 3, bytes.Repeat([]byte{0x01}, 32))
		lhBuf = pbAppendBytes(lhBuf, 4, bytes.Repeat([]byte{0x02}, 32))
		lhBuf = pbAppendBytes(lhBuf, 5, bytes.Repeat([]byte{0x03}, 32))

		var hBuf []byte
		hBuf = pbAppendMsg(hBuf, 1, lhBuf)

		var buf []byte
		buf = pbAppendMsg(buf, 1, hBuf)

		_, err := DecodeMisbehaviour(buf)
		want := "cometbls: TimeNanos out of range"
		if err == nil {
			t.Fatal("expected error for TimeNanos >= 1e9")
		}
		if err.Error() != want {
			t.Fatalf("error: got %q want %q", err.Error(), want)
		}
	})

	t.Run("short_next_validators_hash", func(t *testing.T) {
		var ts []byte
		ts = pbAppendInt64(ts, 1, 1)

		var lh []byte
		lh = pbAppendInt64(lh, 1, 1)
		lh = pbAppendMsg(lh, 2, ts)
		lh = pbAppendBytes(lh, 3, bytes.Repeat([]byte{0x01}, 32))
		lh = pbAppendBytes(lh, 4, bytes.Repeat([]byte{0x02}, 31))
		lh = pbAppendBytes(lh, 5, bytes.Repeat([]byte{0x03}, 32))

		var h []byte
		h = pbAppendMsg(h, 1, lh)

		var buf []byte
		buf = pbAppendMsg(buf, 1, h)

		_, err := DecodeMisbehaviour(buf)
		want := "cometbls: next validators hash must be 32 bytes"
		if err == nil {
			t.Fatal("expected error for short next validators hash")
		}
		if err.Error() != want {
			t.Fatalf("error got %q want %q", err.Error(), want)
		}
	})

	t.Run("wrong_wire_type_on_nested_light_header_field", func(t *testing.T) {
		// HeaderA -> SignedHeader -> Height. The innermost Height field is
		// varint (wire 0), so length-delimited wire type must be rejected.
		buf := []byte{0x0A, 0x04, 0x0A, 0x02, 0x0A, 0x00}
		_, err := DecodeMisbehaviour(buf)
		if err == nil {
			t.Fatal("expected error for nested light header wire-type mismatch")
		}
		if err.Error() != "proto: unexpected wire type for field 1" {
			t.Fatalf("error got %q", err.Error())
		}
	})
}

func TestEncodeDecodeMisbehaviourRoundTrip(t *testing.T) {
	hdrHex := "0a72" +
		"08de81b7f50d" +
		"1204080110011a20" + "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" +
		"2220" + "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" +
		"2a20" + "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" +
		"120210641a037a6b70"
	buf := mustHex("0a7d" + hdrHex + "127d" + hdrHex)
	got, err := DecodeMisbehaviour(buf)
	if err != nil {
		t.Fatalf("DecodeMisbehaviour: %v", err)
	}
	reenc := EncodeMisbehaviour(got)
	bytesEq(t, "Misbehaviour round-trip", reenc, buf)
}
