package core

import (
	"encoding/hex"
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
	"gno.land/p/nt/ufmt/v0"
	"gno.land/p/onbloc/ibc/union/types"
)

func TestPacketCommitmentHashes(cur realm, t *testing.T) {
	cases := []struct {
		name   string
		assert func(*testing.T)
	}{
		{
			"commit packet hash empty data",
			func(t *testing.T) {
				packet := types.Packet{SourceChannelId: 1, DestinationChannelId: 2, TimeoutTimestamp: 1000}
				want := types.MustCommit(types.CommitPacket(packet))
				if got := commitPacketHash(packet); got != want {
					t.Errorf("commitPacketHash: got %s want %s", got.String(), want.String())
				}
			},
		},
		{
			"commit packet hash payload data",
			func(t *testing.T) {
				packet := types.Packet{SourceChannelId: 1, DestinationChannelId: 2, Data: types.Bytes("payload"), TimeoutTimestamp: 1000}
				want := types.MustCommit(types.CommitPacket(packet))
				if got := commitPacketHash(packet); got != want {
					t.Errorf("commitPacketHash: got %s want %s", got.String(), want.String())
				}
			},
		},
		{
			"commit packets hash",
			func(t *testing.T) {
				packets := []types.Packet{
					{SourceChannelId: 1, DestinationChannelId: 2, Data: types.Bytes("a"), TimeoutTimestamp: 1000},
					{SourceChannelId: 1, DestinationChannelId: 2, Data: types.Bytes("b"), TimeoutTimestamp: 1000},
				}
				want := types.MustCommit(types.CommitPackets(packets))
				if got := commitPacketsHash(packets); got != want {
					t.Errorf("commitPacketsHash: got %s want %s", got.String(), want.String())
				}
			},
		},
		{
			"packet commitment path differentiates payloads",
			func(t *testing.T) {
				p1 := types.Packet{SourceChannelId: 1, DestinationChannelId: 2, TimeoutTimestamp: 1000}
				p2 := types.Packet{SourceChannelId: 1, DestinationChannelId: 2, Data: types.Bytes("different"), TimeoutTimestamp: 1000}
				if packetCommitmentPath(p1) == packetCommitmentPath(p2) {
					t.Error("packets with different Union payloads must have different commitment paths")
				}
			},
		},
		{
			"packet acknowledgement path uses batch receipts path",
			func(t *testing.T) {
				packet := types.Packet{SourceChannelId: 1, DestinationChannelId: 2, TimeoutTimestamp: 1000}
				batchHash := commitPacketHash(packet)
				if packetAcknowledgementPath(packet) != types.BatchReceiptsPath(batchHash) {
					t.Error("packet acknowledgement path must use Union batch receipts path")
				}
			},
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, tc.assert)
	}
}

func TestCorePureSurfaceHelpers(cur realm, t *testing.T) {
	packet := types.Packet{SourceChannelId: 1, DestinationChannelId: 2, Data: types.Bytes("payload"), TimeoutTimestamp: 1000}
	packets := []types.Packet{packet}
	connection := types.Connection{State: types.ConnectionStateOpen, ClientId: 1, CounterpartyClientId: 2, CounterpartyConnectionId: 3}
	channel := types.Channel{State: types.ChannelStateOpen, ConnectionId: 1, CounterpartyChannelId: 2, Version: "v1"}

	cases := []struct {
		name   string
		assert func(*testing.T)
	}{
		{
			"CommitPacketHash",
			func(t *testing.T) {
				if got, want := CommitPacketHash(packet), commitPacketHash(packet); got != want {
					t.Errorf("CommitPacketHash: got %s want %s", got.String(), want.String())
				}
			},
		},
		{
			"CommitPacketsHash",
			func(t *testing.T) {
				if got, want := CommitPacketsHash(packets), commitPacketsHash(packets); got != want {
					t.Errorf("CommitPacketsHash: got %s want %s", got.String(), want.String())
				}
			},
		},
		{
			"ConnectionValue",
			func(t *testing.T) {
				if got, want := ConnectionValue(connection), connectionValue(connection); got != want {
					t.Errorf("ConnectionValue: got %s want %s", got.String(), want.String())
				}
			},
		},
		{
			"ChannelValue",
			func(t *testing.T) {
				if got, want := ChannelValue(channel), channelValue(channel); got != want {
					t.Errorf("ChannelValue: got %s want %s", got.String(), want.String())
				}
			},
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, tc.assert)
	}
}

func TestStateValueEncoding(cur realm, t *testing.T) {
	cases := []struct {
		name   string
		assert func(*testing.T)
	}{
		{
			"channel value differentiates states",
			func(t *testing.T) {
				open := types.Channel{State: types.ChannelStateOpen, ConnectionId: 1, CounterpartyChannelId: 2, Version: "v1"}
				closed := types.Channel{State: types.ChannelStateClosed, ConnectionId: 1, CounterpartyChannelId: 2, Version: "v1"}
				if channelValue(open) == channelValue(closed) {
					t.Error("different channel states must encode differently")
				}
			},
		},
		{
			"channel value union integration vector",
			func(t *testing.T) {
				channel := types.Channel{
					State:                 types.ChannelStateInit,
					ConnectionId:          3,
					CounterpartyChannelId: 0,
					CounterpartyPortId:    types.Bytes(mustHex("5fbe74a283f7954f10aa04c2edf55578811aeb03")),
					Version:               "ucs03-zkgm-0",
				}
				want := "0x00781657f014fd25772f10edb002612aa3839e958adf1aa1d2c0f7a44758da26"
				assertH256Hex(t, "union integration vector", channelValue(channel), want)
			},
		},
		{
			"connection value differentiates states",
			func(t *testing.T) {
				open := types.Connection{State: types.ConnectionStateOpen, ClientId: 1, CounterpartyClientId: 2, CounterpartyConnectionId: 3}
				init := types.Connection{State: types.ConnectionStateInit, ClientId: 1, CounterpartyClientId: 2, CounterpartyConnectionId: 3}
				if connectionValue(open) == connectionValue(init) {
					t.Error("different connection states must encode differently")
				}
			},
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, tc.assert)
	}
}

func TestHexEncoding(cur realm, t *testing.T) {
	cases := []struct {
		name   string
		assert func(*testing.T)
	}{
		{
			"hex string empty",
			func(t *testing.T) {
				if got := hexString([]byte{}); got != "0x" {
					t.Errorf("hexString empty: got %q want \"0x\"", got)
				}
			},
		},
		{
			"hex string binary",
			func(t *testing.T) {
				if got := hexString([]byte{0, 15, 255}); got != "0x000fff" {
					t.Errorf("hexString binary: got %q want \"0x000fff\"", got)
				}
			},
		},
		{
			"hex attr empty",
			func(t *testing.T) {
				if got := hexAttr([]byte{}); got != "0x" {
					t.Errorf("hexAttr empty: got %q want \"0x\"", got)
				}
			},
		},
		{
			"hex attr binary",
			func(t *testing.T) {
				if got := hexAttr([]byte{0, 15, 255}); got != "0x000fff" {
					t.Errorf("hexAttr binary: got %q want \"0x000fff\"", got)
				}
			},
		},
		{
			"h256 bytes encoding",
			func(t *testing.T) {
				h := types.H256{0x01, 0x02, 0x03}
				got := h256Bytes(h)
				if hexString(got) != "0x0102030000000000000000000000000000000000000000000000000000000000" {
					t.Errorf("h256Bytes: got %s", hexString(got))
				}
			},
		},
		{
			"h256 bytes does not alias input",
			func(t *testing.T) {
				h := types.H256{0x01, 0x02, 0x03}
				got := h256Bytes(h)
				got[0] = 0xff
				if h[0] != 0x01 {
					t.Fatal("h256Bytes must not alias input array")
				}
			},
		},
		{
			"h256 string encoding",
			func(t *testing.T) {
				h := types.H256{0x01, 0x02, 0x03}
				want := "0x0102030000000000000000000000000000000000000000000000000000000000"
				if got := h256String(h); got != want {
					t.Errorf("h256String: got %q want %q", got, want)
				}
			},
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, tc.assert)
	}
}

// TestHexVsBase64Encoding feeds the same byte input to hexString and
// base64String and compares the two encodings side by side across byte lengths.
// For each length it asserts the expected output string and the expected string
// length: hex is "0x" + 2 chars/byte (2 + 2n), base64 is 4 chars per 3-byte
// group with padding (4 * ceil(n/3)). The two encodings of the same bytes must
// always differ.
func TestHexVsBase64Encoding(cur realm, t *testing.T) {
	// repeating 0x00 0x0f 0xff pattern so each extra byte changes both encodings.
	sample := func(n int) []byte {
		pattern := []byte{0x00, 0x0f, 0xff}
		out := make([]byte, n)
		for i := 0; i < n; i++ {
			out[i] = pattern[i%len(pattern)]
		}
		return out
	}

	cases := []struct {
		n int
		// wantHexLen/wantBase64Len are the predicted output string lengths:
		// hex = 2 ("0x") + 2*n, base64 = 4 * ceil(n/3). Spelled out per case so
		// the expectation is explicit, and cross-checked against the formula.
		wantHexLen    int
		wantBase64Len int
	}{
		{
			n:             0,
			wantHexLen:    2,
			wantBase64Len: 0,
		},
		{
			n:             1,
			wantHexLen:    4,
			wantBase64Len: 4,
		},
		{
			n:             2,
			wantHexLen:    6,
			wantBase64Len: 4,
		},
		{
			n:             3,
			wantHexLen:    8,
			wantBase64Len: 4,
		},
		{
			n:             4,
			wantHexLen:    10,
			wantBase64Len: 8,
		},
		{
			n:             5,
			wantHexLen:    12,
			wantBase64Len: 8,
		},
		{
			n:             6,
			wantHexLen:    14,
			wantBase64Len: 8,
		},
		{
			n:             100,
			wantHexLen:    202,
			wantBase64Len: 136,
		},
		{ // ZKGM Packet Size Test
			n:             800,
			wantHexLen:    1602,
			wantBase64Len: 1068,
		},
		{
			n:             1000,
			wantHexLen:    2002,
			wantBase64Len: 1336,
		},
	}

	for _, tc := range cases {
		t.Run(ufmt.Sprintf("len_%d", tc.n), func(t *testing.T) {
			in := sample(tc.n)

			gotHex := hexString(in)
			gotB64 := base64String(in)

			// the hand-written predicted lengths must match the length formulas
			// (hex = 2 + 2n, base64 = 4 * ceil(n/3)). This guards the table itself.
			uassert.Equal(t, 2+2*tc.n, tc.wantHexLen)
			uassert.Equal(t, 4*((tc.n+2)/3), tc.wantBase64Len)

			// predicted output lengths hold at every size.
			uassert.Equal(t, tc.wantHexLen, len(gotHex))
			uassert.Equal(t, tc.wantBase64Len, len(gotB64))

			// hex is always the "0x" prefix followed by lowercase hex; decoding
			// the body must round-trip back to the original bytes at any length.
			uassert.True(t, strings.HasPrefix(gotHex, "0x"))
			decoded, err := hex.DecodeString(gotHex[2:])
			uassert.NoError(t, err)
			uassert.Equal(t, string(in), string(decoded))

			// the two encodings of identical bytes must never collide
			// (the empty input is the sole exception: "0x" vs "").
			if tc.n > 0 && gotHex == gotB64 {
				t.Errorf("hex and base64 must differ for the same input: %q", gotHex)
			}
		})
	}
}

func TestCloning(cur realm, t *testing.T) {
	cases := []struct {
		name   string
		assert func(*testing.T)
	}{
		{
			"clone channel does not alias fields",
			func(t *testing.T) {
				in := types.Channel{
					State:              types.ChannelStateOpen,
					ConnectionId:       1,
					CounterpartyPortId: types.Bytes{1, 2, 3},
					Version:            "v1",
				}
				got := cloneChannel(in)
				got.CounterpartyPortId[0] = 9
				if in.CounterpartyPortId[0] == 9 {
					t.Fatal("cloneChannel must not alias CounterpartyPortId")
				}
			},
		},
		{
			"clone bytes nil",
			func(t *testing.T) {
				got := types.CloneBytes(nil)
				if got != nil {
					t.Fatal("nil input must remain nil")
				}
			},
		},
		{
			"clone bytes empty",
			func(t *testing.T) {
				got := types.CloneBytes([]byte{})
				if len(got) != 0 {
					t.Fatalf("len: got %d want 0", len(got))
				}
			},
		},
		{
			"clone bytes value",
			func(t *testing.T) {
				in := []byte{1, 2, 3}
				got := types.CloneBytes(in)
				if len(got) != len(in) {
					t.Fatalf("len: got %d want %d", len(got), len(in))
				}
				got[0] = 9
				if in[0] == 9 {
					t.Fatal("clone must not alias input")
				}
			},
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, tc.assert)
	}
}
