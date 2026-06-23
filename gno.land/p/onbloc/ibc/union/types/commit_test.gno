package types

import "testing"

func TestCommitPackets(t *testing.T) {
	tests := []struct {
		name    string
		packets []Packet
		want    string
	}{
		{
			name:    "empty",
			packets: nil,
			want:    "569e75fc77c1a856f6daaf9e69d8a9566ca34aa47f9133711ce065a571af0cfd",
		},
		{
			name: "single packet",
			packets: []Packet{
				{
					SourceChannelId:      1,
					DestinationChannelId: 2,
					Data:                 []byte{0xab, 0xcd},
					TimeoutHeight:        0,
					TimeoutTimestamp:     3,
				},
			},
			want: "31f771c1d8ee88a4676e6da4cc884fbfecb6e7a7ca033f7f3612a14893ac51e3",
		},
		{
			name: "two packets",
			packets: []Packet{
				{
					SourceChannelId:      1,
					DestinationChannelId: 2,
					Data:                 []byte{0xab, 0xcd},
					TimeoutHeight:        0,
					TimeoutTimestamp:     3,
				},
				{
					SourceChannelId:      3,
					DestinationChannelId: 4,
					Data:                 []byte{0x12, 0x34},
					TimeoutHeight:        0,
					TimeoutTimestamp:     5,
				},
			},
			want: "d795c5454ae1091c92168b9bfc9a7b10ae68fce29157b882904d69b19ef949cb",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got, err := CommitPackets(tc.packets)
			if err != nil {
				t.Fatalf("CommitPackets error: %v", err)
			}
			assertHex(t, tc.name, got[:], tc.want)
		})
	}
}

func TestCommitAcks(t *testing.T) {
	tests := []struct {
		name string
		acks [][]byte
		want string
	}{
		{
			name: "empty",
			acks: nil,
			want: "019e75fc77c1a856f6daaf9e69d8a9566ca34aa47f9133711ce065a571af0cfd",
		},
		{
			name: "single ack",
			acks: [][]byte{
				{0xab, 0xcd},
			},
			want: "0108036852460acf48664bdbb4d99f13e8845c1c0e5b46608995e98bfb707f9e",
		},
		{
			name: "two acks",
			acks: [][]byte{
				{0xab, 0xcd},
				{0x12, 0x34},
			},
			want: "018d1833041ca53600fa7b8824af32ae57486b06d58bffc8481dc14336bea35a",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := CommitAcks(tc.acks)
			assertHex(t, tc.name, got[:], tc.want)
		})
	}
}

func TestCommitPacket(t *testing.T) {
	tests := []struct {
		name   string
		packet Packet
		want   string
	}{
		{
			name: "empty data",
			packet: Packet{
				SourceChannelId:      1,
				DestinationChannelId: 2,
				Data:                 nil,
				TimeoutHeight:        0,
				TimeoutTimestamp:     100,
			},
			want: "c44210ccbbc75298ed35e9a1d03a9cc47f80b47157f280488abbceeac8a2dacc",
		},
		{
			name: "single byte data",
			packet: Packet{
				SourceChannelId:      5,
				DestinationChannelId: 10,
				Data:                 []byte{0xaa},
				TimeoutHeight:        0,
				TimeoutTimestamp:     200,
			},
			want: "72c94facb1f818f209e3031106ed6c2caff6660887ac53ceab341a4fbd11a5f4",
		},
		{
			name: "multi byte data",
			packet: Packet{
				SourceChannelId:      1,
				DestinationChannelId: 2,
				Data:                 []byte{0xab, 0xcd},
				TimeoutHeight:        0,
				TimeoutTimestamp:     3,
			},
			want: "31f771c1d8ee88a4676e6da4cc884fbfecb6e7a7ca033f7f3612a14893ac51e3",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got, err := CommitPacket(tc.packet)
			if err != nil {
				t.Fatalf("CommitPacket error: %v", err)
			}
			assertHex(t, tc.name, got[:], tc.want)
		})
	}
}

func TestCommitAck(t *testing.T) {
	tests := []struct {
		name string
		ack  []byte
		want string
	}{
		{
			name: "single ack byte",
			ack:  []byte{0xab},
			want: "01260ca8a2d29d0171573f71983914f6099f12d3b3886a9e6910ad855cb4950f",
		},
		{
			name: "ack with multiple bytes",
			ack:  []byte{0xab, 0xcd},
			want: "0108036852460acf48664bdbb4d99f13e8845c1c0e5b46608995e98bfb707f9e",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := CommitAck(tc.ack)
			assertHex(t, tc.name, got[:], tc.want)
		})
	}
}

func TestMustCommit(t *testing.T) {
	tests := []struct {
		name  string
		h     H256
		err   error
		want  string
	}{
		{
			name: "success returns hash",
			h: H256{
				0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
				0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f, 0x10,
				0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18,
				0x19, 0x1a, 0x1b, 0x1c, 0x1d, 0x1e, 0x1f, 0x20,
			},
			err:  nil,
			want: "0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := MustCommit(tc.h, tc.err)
			assertHex(t, tc.name, got[:], tc.want)
		})
	}
}
