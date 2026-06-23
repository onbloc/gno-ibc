package storage

import (
	"bytes"
	"testing"
)

func TestDecodeProofRejectsTrailingBytes(t *testing.T) {
	_, err := DecodeProof(mustHex(
		"0200000000000000000000000000000000000000000000000000000000000000" +
			"efbeadde00000000000000000000000000000000000000000000000000000000" +
			"0000000000000000" +
			"ff",
	))
	if err != ErrTrailingProofBytes {
		t.Fatalf("DecodeProof trailing: got %v want %v", err, ErrTrailingProofBytes)
	}
}

func TestDecodeProofRejectsMalformedBytes(t *testing.T) {
	key := reverse32(WordFromUint64(2))
	value := reverse32(WordFromUint64(0xdeadbeef))
	validPrefix := append(append([]byte{}, key...), value...)

	tests := []struct {
		name string
		buf  []byte
		err  error
	}{
		{
			name: "short key",
			buf:  bytes.Repeat([]byte{0x00}, 31),
			err:  ErrInvalidProofBytes,
		},
		{
			name: "short value",
			buf:  append([]byte{}, key...),
			err:  ErrInvalidProofBytes,
		},
		{
			name: "short proof count",
			buf:  append(validPrefix, []byte{0x01, 0x00, 0x00, 0x00}...),
			err:  ErrInvalidProofBytes,
		},
		{
			name: "count larger than buffer",
			buf: func() []byte {
				out := append([]byte{}, validPrefix...)
				out = appendUint64LE(out, 100)
				return out
			}(),
			err: ErrInvalidProofBytes,
		},
		{
			name: "node length missing",
			buf: func() []byte {
				out := append([]byte{}, validPrefix...)
				out = appendUint64LE(out, 1)
				return out
			}(),
			err: ErrInvalidProofBytes,
		},
		{
			name: "node payload truncated",
			buf: func() []byte {
				out := append([]byte{}, validPrefix...)
				out = appendUint64LE(out, 1)
				out = appendUint64LE(out, 3)
				out = append(out, 0xaa, 0xbb)
				return out
			}(),
			err: ErrInvalidProofBytes,
		},
		{
			name: "trailing bytes",
			buf: func() []byte {
				out := append([]byte{}, validPrefix...)
				out = appendUint64LE(out, 0)
				out = append(out, 0xff)
				return out
			}(),
			err: ErrTrailingProofBytes,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, err := DecodeProof(tt.buf)
			if err != tt.err {
				t.Fatalf("DecodeProof: got %v want %v", err, tt.err)
			}
		})
	}
}

func TestEncodeProofBoundaries(t *testing.T) {
	tests := []struct {
		name  string
		proof Proof
		want  string
	}{
		{
			name: "empty proof zero key value",
			proof: Proof{
				Key:   make([]byte, 32),
				Value: make([]byte, 32),
				Proof: nil,
			},
			want: "0000000000000000000000000000000000000000000000000000000000000000" +
				"0000000000000000000000000000000000000000000000000000000000000000" +
				"0000000000000000",
		},
		{
			name: "max key value and zero length node",
			proof: Proof{
				Key:   bytes.Repeat([]byte{0xff}, 32),
				Value: bytes.Repeat([]byte{0xff}, 32),
				Proof: [][]byte{
					nil,
				},
			},
			want: "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff" +
				"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff" +
				"0100000000000000" +
				"0000000000000000",
		},
		{
			name: "short key value are reverse padded",
			proof: Proof{
				Key:   []byte{0x01, 0x02},
				Value: []byte{0x03},
				Proof: [][]byte{
					{0xaa, 0xbb},
				},
			},
			want: "0201000000000000000000000000000000000000000000000000000000000000" +
				"0300000000000000000000000000000000000000000000000000000000000000" +
				"0100000000000000" +
				"0200000000000000" +
				"aabb",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assertHex(t, "EncodeProof", EncodeProof(tt.proof), tt.want)
		})
	}
}

func TestReadU256(t *testing.T) {
	tests := []struct {
		name    string
		buf     []byte
		want    []byte
		wantPos int
		err     error
	}{
		{name: "short", buf: bytes.Repeat([]byte{0x00}, 31), err: ErrInvalidProofBytes},
		{name: "exact zero", buf: bytes.Repeat([]byte{0x00}, 32), want: bytes.Repeat([]byte{0x00}, 32), wantPos: 32},
		{name: "exact max", buf: bytes.Repeat([]byte{0xff}, 32), want: bytes.Repeat([]byte{0xff}, 32), wantPos: 32},
		{name: "extra bytes", buf: append(reverse32(WordFromUint64(0x0102)), 0xff), want: WordFromUint64(0x0102), wantPos: 32},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			d := proofDecoder{buf: tt.buf}
			got, err := d.readU256()
			if err != tt.err {
				t.Fatalf("readU256: got err %v want %v", err, tt.err)
			}
			if err != nil {
				return
			}
			if d.pos != tt.wantPos || !bytes.Equal(got, tt.want) {
				t.Fatalf("readU256: got value=%x pos=%d want value=%x pos=%d", got, d.pos, tt.want, tt.wantPos)
			}
		})
	}
}

func TestReadBytes(t *testing.T) {
	tests := []struct {
		name    string
		buf     []byte
		want    []byte
		wantPos int
		err     error
	}{
		{name: "missing length", buf: []byte{0x01}, err: ErrInvalidProofBytes},
		{name: "zero length", buf: appendUint64LE(nil, 0), want: []byte{}, wantPos: 8},
		{name: "exact remaining", buf: append(appendUint64LE(nil, 3), 0xaa, 0xbb, 0xcc), want: []byte{0xaa, 0xbb, 0xcc}, wantPos: 11},
		{name: "payload truncated", buf: append(appendUint64LE(nil, 3), 0xaa, 0xbb), err: ErrInvalidProofBytes},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			d := proofDecoder{buf: tt.buf}
			got, err := d.readBytes()
			if err != tt.err {
				t.Fatalf("readBytes: got err %v want %v", err, tt.err)
			}
			if err != nil {
				return
			}
			if d.pos != tt.wantPos || !bytes.Equal(got, tt.want) {
				t.Fatalf("readBytes: got value=%x pos=%d want value=%x pos=%d", got, d.pos, tt.want, tt.wantPos)
			}
		})
	}
}

func TestReadUint64(t *testing.T) {
	tests := []struct {
		name    string
		buf     []byte
		want    uint64
		wantPos int
		err     error
	}{
		{name: "short", buf: []byte{0x01, 0x02}, err: ErrInvalidProofBytes},
		{name: "exact", buf: []byte{0x08, 0x07, 0x06, 0x05, 0x04, 0x03, 0x02, 0x01}, want: 0x0102030405060708, wantPos: 8},
		{name: "extra", buf: []byte{0xff, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xaa}, want: 0xff, wantPos: 8},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			d := proofDecoder{buf: tt.buf}
			got, err := d.readUint64()
			if err != tt.err {
				t.Fatalf("readUint64: got err %v want %v", err, tt.err)
			}
			if err != nil {
				return
			}
			if d.pos != tt.wantPos || got != tt.want {
				t.Fatalf("readUint64: got value=%d pos=%d want value=%d pos=%d", got, d.pos, tt.want, tt.wantPos)
			}
		})
	}
}

func TestAppendUint64LE(t *testing.T) {
	tests := []struct {
		name string
		v    uint64
		want string
	}{
		{name: "zero", v: 0, want: "0000000000000000"},
		{name: "one", v: 1, want: "0100000000000000"},
		{name: "multi byte", v: 0x0102030405060708, want: "0807060504030201"},
		{name: "max", v: ^uint64(0), want: "ffffffffffffffff"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assertHex(t, "appendUint64LE", appendUint64LE(nil, tt.v), tt.want)
		})
	}
}

func TestReverse32(t *testing.T) {
	tests := []struct {
		name string
		in   []byte
		want string
	}{
		{name: "empty", in: nil, want: "0000000000000000000000000000000000000000000000000000000000000000"},
		{name: "short", in: []byte{0x01, 0x02, 0x03}, want: "0302010000000000000000000000000000000000000000000000000000000000"},
		{name: "exact", in: mustHex("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"), want: "1f1e1d1c1b1a191817161514131211100f0e0d0c0b0a09080706050403020100"},
		{name: "long truncates to last 32 bytes reversed by source end", in: append([]byte{0xaa}, mustHex("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f")...), want: "1f1e1d1c1b1a191817161514131211100f0e0d0c0b0a09080706050403020100"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assertHex(t, "reverse32", reverse32(tt.in), tt.want)
		})
	}
}
