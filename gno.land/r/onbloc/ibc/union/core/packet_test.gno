package core

import (
	"testing"

	"gno.land/p/onbloc/ibc/union/types"
)

func TestQueryBatchPackets(cur realm, t *testing.T) {
	cases := []struct {
		name      string
		channelId types.ChannelId
		batchHash types.H256
		setup     func()
		wantEmpty bool
	}{
		{
			name:      "existing commitment returns hex string",
			channelId: 1,
			batchHash: types.Keccak([]byte("batch1")),
			setup: func() {
				store.setCommitment(types.BatchPacketsPath(types.Keccak([]byte("batch1"))), types.Keccak([]byte("value1")))
			},
			wantEmpty: false,
		},
		{
			name:      "zero hash commitment",
			channelId: 2,
			batchHash: types.H256{},
			setup: func() {
				var zero types.H256
				store.setCommitment(types.BatchPacketsPath(zero), zero)
			},
			wantEmpty: false,
		},
		{
			name:      "nonexistent commitment returns empty",
			channelId: 3,
			batchHash: types.Keccak([]byte("nonexistent")),
			setup:     func() {},
			wantEmpty: true,
		},
		{
			name:      "channelId ignored commitment exists",
			channelId: 999,
			batchHash: types.Keccak([]byte("batch2")),
			setup: func() {
				store.setCommitment(types.BatchPacketsPath(types.Keccak([]byte("batch2"))), types.Keccak([]byte("value2")))
			},
			wantEmpty: false,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			resetStore(cur)
			tc.setup()
			got := QueryBatchPackets(tc.channelId, tc.batchHash)
			isEmpty := got == ""
			if isEmpty != tc.wantEmpty {
				t.Errorf("QueryBatchPackets empty: got %v want %v (got=%q)", isEmpty, tc.wantEmpty, got)
			}
			if !tc.wantEmpty && got == "" {
				t.Errorf("QueryBatchPackets: got empty want non-empty")
			}
		})
	}
}

func TestQueryBatchReceipts(cur realm, t *testing.T) {
	cases := []struct {
		name      string
		channelId types.ChannelId
		batchHash types.H256
		setup     func()
		wantEmpty bool
	}{
		{
			name:      "existing receipt returns hex string",
			channelId: 1,
			batchHash: types.Keccak([]byte("receipt1")),
			setup: func() {
				store.setCommitment(types.BatchReceiptsPath(types.Keccak([]byte("receipt1"))), types.Keccak([]byte("receipt-value")))
			},
			wantEmpty: false,
		},
		{
			name:      "nonexistent receipt returns empty",
			channelId: 2,
			batchHash: types.Keccak([]byte("nonexistent-receipt")),
			setup:     func() {},
			wantEmpty: true,
		},
		{
			name:      "COMMITMENT_MAGIC receipt",
			channelId: 3,
			batchHash: types.Keccak([]byte("magic-receipt")),
			setup: func() {
				store.setCommitment(types.BatchReceiptsPath(types.Keccak([]byte("magic-receipt"))), types.COMMITMENT_MAGIC)
			},
			wantEmpty: false,
		},
		{
			name:      "COMMITMENT_MAGIC_ACK receipt",
			channelId: 4,
			batchHash: types.Keccak([]byte("ack-receipt")),
			setup: func() {
				store.setCommitment(types.BatchReceiptsPath(types.Keccak([]byte("ack-receipt"))), types.COMMITMENT_MAGIC_ACK)
			},
			wantEmpty: false,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			resetStore(cur)
			tc.setup()
			got := QueryBatchReceipts(tc.channelId, tc.batchHash)
			isEmpty := got == ""
			if isEmpty != tc.wantEmpty {
				t.Errorf("QueryBatchReceipts empty: got %v want %v (got=%q)", isEmpty, tc.wantEmpty, got)
			}
			if !tc.wantEmpty && got == "" {
				t.Errorf("QueryBatchReceipts: got empty want non-empty")
			}
		})
	}
}

func TestQueryCommitmentAtPath(cur realm, t *testing.T) {
	cases := []struct {
		name      string
		channelId types.ChannelId
		path      types.H256
		setup     func()
		wantEmpty bool
	}{
		{
			name:      "existing commitment returns hex string",
			channelId: 1,
			path:      types.Keccak([]byte("custom-path")),
			setup: func() {
				store.setCommitment(types.Keccak([]byte("custom-path")), types.Keccak([]byte("commitment-value")))
			},
			wantEmpty: false,
		},
		{
			name:      "nonexistent commitment returns empty",
			channelId: 2,
			path:      types.Keccak([]byte("missing-path")),
			setup:     func() {},
			wantEmpty: true,
		},
		{
			name:      "zero path value",
			channelId: 3,
			path:      types.H256{},
			setup: func() {
				var zero types.H256
				store.setCommitment(zero, types.Keccak([]byte("zero-path-value")))
			},
			wantEmpty: false,
		},
		{
			name:      "channelId ignored commitment exists",
			channelId: 999,
			path:      types.Keccak([]byte("ignored-channel")),
			setup: func() {
				store.setCommitment(types.Keccak([]byte("ignored-channel")), types.Keccak([]byte("channel-ignored-value")))
			},
			wantEmpty: false,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			resetStore(cur)
			tc.setup()
			got := QueryCommitmentAtPath(tc.channelId, tc.path)
			isEmpty := got == ""
			if isEmpty != tc.wantEmpty {
				t.Errorf("QueryCommitmentAtPath empty: got %v want %v (got=%q)", isEmpty, tc.wantEmpty, got)
			}
			if !tc.wantEmpty && got == "" {
				t.Errorf("QueryCommitmentAtPath: got empty want non-empty")
			}
		})
	}
}

func TestQueryReceiptAtPath(cur realm, t *testing.T) {
	cases := []struct {
		name      string
		channelId types.ChannelId
		path      types.H256
		setup     func()
		wantEmpty bool
	}{
		{
			name:      "existing receipt returns hex string",
			channelId: 1,
			path:      types.Keccak([]byte("receipt-path")),
			setup: func() {
				store.setCommitment(types.Keccak([]byte("receipt-path")), types.Keccak([]byte("receipt-commitment")))
			},
			wantEmpty: false,
		},
		{
			name:      "nonexistent receipt returns empty",
			channelId: 2,
			path:      types.Keccak([]byte("missing-receipt")),
			setup:     func() {},
			wantEmpty: true,
		},
		{
			name:      "acknowledged receipt",
			channelId: 3,
			path:      types.Keccak([]byte("acked-path")),
			setup: func() {
				store.setCommitment(types.Keccak([]byte("acked-path")), types.COMMITMENT_MAGIC_ACK)
			},
			wantEmpty: false,
		},
		{
			name:      "magic value receipt",
			channelId: 4,
			path:      types.Keccak([]byte("magic-path")),
			setup: func() {
				store.setCommitment(types.Keccak([]byte("magic-path")), types.COMMITMENT_MAGIC)
			},
			wantEmpty: false,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			resetStore(cur)
			tc.setup()
			got := QueryReceiptAtPath(tc.channelId, tc.path)
			isEmpty := got == ""
			if isEmpty != tc.wantEmpty {
				t.Errorf("QueryReceiptAtPath empty: got %v want %v (got=%q)", isEmpty, tc.wantEmpty, got)
			}
			if !tc.wantEmpty && got == "" {
				t.Errorf("QueryReceiptAtPath: got empty want non-empty")
			}
		})
	}
}

func TestGetCommittedMembershipProof(cur realm, t *testing.T) {
	cases := []struct {
		name        string
		clientId    types.ClientId
		proofHeight uint64
		path        []byte
		setup       func()
		wantEmpty   bool
	}{
		{
			name:        "existing membership proof returns hex string",
			clientId:    1,
			proofHeight: 100,
			path:        []byte("proof-path-1"),
			setup: func() {
				store.saveMembershipProof(1, 100, []byte("proof-path-1"), types.Keccak([]byte("proof-value")))
			},
			wantEmpty: false,
		},
		{
			name:        "nonexistent proof returns empty",
			clientId:    2,
			proofHeight: 200,
			path:        []byte("missing-proof"),
			setup:       func() {},
			wantEmpty:   true,
		},
		{
			name:        "zero height proof",
			clientId:    3,
			proofHeight: 0,
			path:        []byte("zero-height"),
			setup: func() {
				store.saveMembershipProof(3, 0, []byte("zero-height"), types.Keccak([]byte("zero-height-value")))
			},
			wantEmpty: false,
		},
		{
			name:        "empty path proof",
			clientId:    4,
			proofHeight: 50,
			path:        []byte{},
			setup: func() {
				store.saveMembershipProof(4, 50, []byte{}, types.Keccak([]byte("empty-path-value")))
			},
			wantEmpty: false,
		},
		{
			name:        "wrong clientId returns empty",
			clientId:    999,
			proofHeight: 100,
			path:        []byte("proof-path-1"),
			setup: func() {
				store.saveMembershipProof(1, 100, []byte("proof-path-1"), types.Keccak([]byte("proof-value")))
			},
			wantEmpty: true,
		},
		{
			name:        "wrong height returns empty",
			clientId:    1,
			proofHeight: 999,
			path:        []byte("proof-path-1"),
			setup: func() {
				store.saveMembershipProof(1, 100, []byte("proof-path-1"), types.Keccak([]byte("proof-value")))
			},
			wantEmpty: true,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			resetStore(cur)
			tc.setup()
			got := GetCommittedMembershipProof(tc.clientId, tc.proofHeight, tc.path)
			isEmpty := got == ""
			if isEmpty != tc.wantEmpty {
				t.Errorf("GetCommittedMembershipProof empty: got %v want %v (got=%q)", isEmpty, tc.wantEmpty, got)
			}
			if !tc.wantEmpty && got == "" {
				t.Errorf("GetCommittedMembershipProof: got empty want non-empty")
			}
		})
	}
}

func TestGetCommittedNonMembershipProof(cur realm, t *testing.T) {
	cases := []struct {
		name        string
		clientId    types.ClientId
		proofHeight uint64
		path        []byte
		setup       func()
		want        bool
	}{
		{
			name:        "existing non-membership proof returns true",
			clientId:    1,
			proofHeight: 100,
			path:        []byte("non-member-path"),
			setup: func() {
				store.saveNonMembershipProof(1, 100, []byte("non-member-path"), types.NON_MEMBERSHIP_COMMITMENT_VALUE)
			},
			want: true,
		},
		{
			name:        "nonexistent non-membership proof returns false",
			clientId:    2,
			proofHeight: 200,
			path:        []byte("missing-non-member"),
			setup:       func() {},
			want:        false,
		},
		{
			name:        "wrong value returns false",
			clientId:    3,
			proofHeight: 150,
			path:        []byte("wrong-value-path"),
			setup: func() {
				store.saveNonMembershipProof(3, 150, []byte("wrong-value-path"), types.Keccak([]byte("wrong-value")))
			},
			want: false,
		},
		{
			name:        "zero height non-membership proof",
			clientId:    4,
			proofHeight: 0,
			path:        []byte("zero-height-path"),
			setup: func() {
				store.saveNonMembershipProof(4, 0, []byte("zero-height-path"), types.NON_MEMBERSHIP_COMMITMENT_VALUE)
			},
			want: true,
		},
		{
			name:        "empty path non-membership proof",
			clientId:    5,
			proofHeight: 50,
			path:        []byte{},
			setup: func() {
				store.saveNonMembershipProof(5, 50, []byte{}, types.NON_MEMBERSHIP_COMMITMENT_VALUE)
			},
			want: true,
		},
		{
			name:        "wrong clientId returns false",
			clientId:    999,
			proofHeight: 100,
			path:        []byte("non-member-path"),
			setup: func() {
				store.saveNonMembershipProof(1, 100, []byte("non-member-path"), types.NON_MEMBERSHIP_COMMITMENT_VALUE)
			},
			want: false,
		},
		{
			name:        "wrong height returns false",
			clientId:    1,
			proofHeight: 999,
			path:        []byte("non-member-path"),
			setup: func() {
				store.saveNonMembershipProof(1, 100, []byte("non-member-path"), types.NON_MEMBERSHIP_COMMITMENT_VALUE)
			},
			want: false,
		},
		{
			name:        "COMMITMENT_MAGIC returns false",
			clientId:    6,
			proofHeight: 75,
			path:        []byte("magic-path"),
			setup: func() {
				store.saveNonMembershipProof(6, 75, []byte("magic-path"), types.COMMITMENT_MAGIC)
			},
			want: false,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			resetStore(cur)
			tc.setup()
			got := GetCommittedNonMembershipProof(tc.clientId, tc.proofHeight, tc.path)
			if got != tc.want {
				t.Errorf("GetCommittedNonMembershipProof: got %v want %v", got, tc.want)
			}
		})
	}
}
