// Test vectors and cases are based on the following references:
//
//	https://ethereum.org/developers/docs/data-structures-and-encoding/rlp/
package rlp

import (
	"bytes"
	"encoding/hex"
	"strings"
	"testing"
)

func TestEncodeBytes(t *testing.T) {
	cases := []struct {
		name string
		in   []byte
		want string
	}{
		{"dog", []byte("dog"), "83646f67"},
		{"empty string", nil, "80"},
		{"zero byte", []byte{0x00}, "00"},
		{"bytes 0400", []byte{0x04, 0x00}, "820400"},
		{"lorem long string", []byte("Lorem ipsum dolor sit amet, consectetur adipisicing elit"), "b8384c6f72656d20697073756d20646f6c6f722073697420616d65742c20636f6e7365637465747572206164697069736963696e6720656c6974"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			assertHex(t, tc.name, EncodeBytes(tc.in), tc.want)
		})
	}
}

func TestEncodeList(t *testing.T) {
	cases := []struct {
		name  string
		items [][]byte
		want  string
	}{
		{"empty list", nil, "c0"},
		{"cat dog list", [][]byte{EncodeBytes([]byte("cat")), EncodeBytes([]byte("dog"))}, "c88363617483646f67"},
		{"set theoretical three", [][]byte{
			EncodeList(),
			EncodeList(EncodeList()),
			EncodeList(EncodeList(), EncodeList(EncodeList())),
		}, "c7c0c1c0c3c0c1c0"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			assertHex(t, tc.name, EncodeList(tc.items...), tc.want)
		})
	}
}

func TestAppendBytes(t *testing.T) {
	cases := []struct {
		name string
		in   []byte
		want string
	}{
		{"single byte zero stays literal", []byte{0x00}, "00"},
		{"single byte 0x7f stays literal", []byte{0x7f}, "7f"},
		{"single byte 0x80 gets string header", []byte{0x80}, "8180"},
		{"fifty five byte string uses short header", bytes.Repeat([]byte{0xaa}, 55), "b7" + strings.Repeat("aa", 55)},
		{"fifty six byte string uses long header", bytes.Repeat([]byte{0xaa}, 56), "b838" + strings.Repeat("aa", 56)},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			assertHex(t, tc.name, appendBytes(nil, tc.in), tc.want)
		})
	}
}

func TestBytesSize(t *testing.T) {
	cases := []struct {
		name string
		in   []byte
		want int
	}{
		{"single byte zero stays literal", []byte{0x00}, 1},
		{"single byte 0x7f stays literal", []byte{0x7f}, 1},
		{"single byte 0x80 includes header", []byte{0x80}, 2},
		{"fifty five byte string", bytes.Repeat([]byte{0xaa}, 55), 56},
		{"fifty six byte string", bytes.Repeat([]byte{0xaa}, 56), 58},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := bytesSize(tc.in); got != tc.want {
				t.Fatalf("bytesSize = %d, want %d", got, tc.want)
			}
		})
	}
}

func TestListSize(t *testing.T) {
	cases := []struct {
		name        string
		contentSize int
		want        int
	}{
		{"empty", 0, 1},
		{"short", 55, 56},
		{"long", 56, 58},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := listSize(tc.contentSize); got != tc.want {
				t.Fatalf("listSize = %d, want %d", got, tc.want)
			}
		})
	}
}

func TestAppendHeader(t *testing.T) {
	cases := []struct {
		name    string
		baseTag byte
		size    uint64
		want    string
	}{
		{"short string empty", 0x80, 0, "80"},
		{"short string max", 0x80, 55, "b7"},
		{"long string", 0x80, 56, "b838"},
		{"short list empty", 0xC0, 0, "c0"},
		{"long list", 0xC0, 56, "f838"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			assertHex(t, tc.name, appendHeader(nil, tc.baseTag, tc.size), tc.want)
		})
	}
}

func TestAppendBigEndianUint(t *testing.T) {
	cases := []struct {
		name string
		x    uint64
		n    int
		want string
	}{
		{"zero bytes", 0xab, 0, ""},
		{"zero one byte", 0, 1, "00"},
		{"one byte", 0xab, 1, "ab"},
		{"eight bytes", 0x0102030405060708, 8, "0102030405060708"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := appendBigEndianUint(nil, tc.x, tc.n)
			if hex.EncodeToString(got) != tc.want {
				t.Fatalf("appendBigEndianUint = %s, want %s", hex.EncodeToString(got), tc.want)
			}
		})
	}
}

func TestHeaderSize(t *testing.T) {
	cases := []struct {
		payload int
		want    int
	}{
		{0, 1},
		{55, 1},
		{56, 2},
		{255, 2},
		{256, 3},
	}
	for _, tc := range cases {
		t.Run("headerSize", func(t *testing.T) {
			if got := headerSize(tc.payload); got != tc.want {
				t.Fatalf("headerSize(%d) = %d, want %d", tc.payload, got, tc.want)
			}
		})
	}
}

func TestIntSize(t *testing.T) {
	cases := []struct {
		in   uint64
		want int
	}{
		{0, 1},
		{1<<8 - 1, 1},
		{1 << 8, 2},
		{1 << 16, 3},
		{1 << 24, 4},
		{1 << 32, 5},
		{1 << 40, 6},
		{1 << 48, 7},
		{1 << 56, 8},
	}
	for _, tc := range cases {
		t.Run("intSize", func(t *testing.T) {
			if got := intSize(tc.in); got != tc.want {
				t.Fatalf("intSize(%d) = %d, want %d", tc.in, got, tc.want)
			}
		})
	}
}
