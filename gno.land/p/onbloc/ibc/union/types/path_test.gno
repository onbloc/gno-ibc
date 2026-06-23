package types

import "testing"

func TestMergeAck(t *testing.T) {
	tests := []struct {
		name string
		ack  H256
		want string
	}{
		{
			name: "sets commitment magic byte",
			ack:  mustH256(t, "aa11111111111111111111111111111111111111111111111111111111111111"),
			want: "0111111111111111111111111111111111111111111111111111111111111111",
		},
		{
			name: "preserves existing magic byte",
			ack:  mustH256(t, "0122222222222222222222222222222222222222222222222222222222222222"),
			want: "0122222222222222222222222222222222222222222222222222222222222222",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			original := tc.ack
			got := mergeAck(tc.ack)
			assertHex(t, tc.name, got[:], tc.want)
			if tc.ack != original {
				t.Fatal("mergeAck mutated caller value")
			}
		})
	}
}
