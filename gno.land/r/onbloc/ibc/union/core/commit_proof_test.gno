package core

import (
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/p/onbloc/ibc/union/types"
)

func setCommitProofAdmin(cur realm) {
	admin = cur.Address()
}

func TestCommitMembershipProofStoresCommittedValue(cur realm, t *testing.T) {
	resetStore()
	oldAdmin := admin
	defer func() { admin = oldAdmin }()
	setCommitProofAdmin(cur)

	client := &mockClient{chainId: "union-1", status: types.StatusActive}
	clientId := registerMockClient(client)
	path := types.Bytes("clients/7/consensusStates/11")
	value := types.Bytes("consensus-state")
	proof := types.Bytes("membership-proof")

	CommitMembershipProof(cross(cur), types.MsgCommitMembershipProof{
		ClientId:    clientId,
		ProofHeight: 10,
		Proof:       proof,
		Path:        path,
		Value:       value,
	})

	if len(client.membershipKeys) != 1 {
		t.Fatalf("membership calls: got %d want 1", len(client.membershipKeys))
	}
	if client.membershipHeights[0] != types.NewHeight(10) ||
		string(client.membershipProofs[0]) != string(proof) ||
		string(client.membershipKeys[0]) != string(path) ||
		string(client.membershipValues[0]) != string(value) {
		t.Fatal("CommitMembershipProof must pass proof height, path, proof, and value through")
	}
	if got := GetCommittedMembershipProof(clientId, 10, path); got != types.Keccak(value).String() {
		t.Fatalf("committed membership proof: got %q want %s", got, types.Keccak(value))
	}
}

func TestCommitMembershipProofRejectsNonAdminBeforeVerification(cur realm, t *testing.T) {
	resetStore()
	oldAdmin := admin
	defer func() { admin = oldAdmin }()
	admin = testutils.TestAddress("different-admin")
	client := &mockClient{chainId: "union-1", status: types.StatusActive}
	clientId := registerMockClient(client)

	uassert.AbortsContains(t, cur, "unauthorized", func(cur realm) {
		CommitMembershipProof(cur, types.MsgCommitMembershipProof{
			ClientId:    clientId,
			ProofHeight: 10,
			Proof:       types.Bytes("proof"),
			Path:        types.Bytes("path"),
			Value:       types.Bytes("value"),
		})
	})

	if len(client.membershipKeys) != 0 {
		t.Fatalf("membership calls: got %d want 0", len(client.membershipKeys))
	}
}

func TestCommitMembershipProofRejectsInactiveClientBeforeVerification(cur realm, t *testing.T) {
	resetStore()
	oldAdmin := admin
	defer func() { admin = oldAdmin }()
	setCommitProofAdmin(cur)
	client := &mockClient{chainId: "union-1", status: types.StatusFrozen}
	clientId := registerMockClient(client)

	uassert.AbortsContains(t, cur, "client is not active", func(cur realm) {
		CommitMembershipProof(cross(cur), types.MsgCommitMembershipProof{
			ClientId:    clientId,
			ProofHeight: 10,
			Proof:       types.Bytes("proof"),
			Path:        types.Bytes("path"),
			Value:       types.Bytes("value"),
		})
	})

	if len(client.membershipKeys) != 0 {
		t.Fatalf("membership calls: got %d want 0", len(client.membershipKeys))
	}
	if got := GetCommittedMembershipProof(clientId, 10, types.Bytes("path")); got != "" {
		t.Fatalf("inactive client must not commit membership proof; got %q", got)
	}
}

func TestCommitNonMembershipProofStoresSentinel(cur realm, t *testing.T) {
	resetStore()
	oldAdmin := admin
	defer func() { admin = oldAdmin }()
	setCommitProofAdmin(cur)

	client := &mockClient{chainId: "union-1", status: types.StatusActive}
	clientId := registerMockClient(client)
	path := types.Bytes("clients/7/consensusStates/11")
	proof := types.Bytes("non-membership-proof")

	CommitNonMembershipProof(cross(cur), types.MsgCommitNonMembershipProof{
		ClientId:    clientId,
		ProofHeight: 10,
		Proof:       proof,
		Path:        path,
	})

	if len(client.nonMembershipKeys) != 1 {
		t.Fatalf("non-membership calls: got %d want 1", len(client.nonMembershipKeys))
	}
	if client.nonMembershipHeights[0] != types.NewHeight(10) ||
		string(client.nonMembershipProofs[0]) != string(proof) ||
		string(client.nonMembershipKeys[0]) != string(path) {
		t.Fatal("CommitNonMembershipProof must pass proof height, path, and proof through")
	}
	if !GetCommittedNonMembershipProof(clientId, 10, path) {
		t.Fatal("CommitNonMembershipProof must store the non-membership sentinel")
	}
}

func TestCommitNonMembershipProofRejectsInactiveClientBeforeVerification(cur realm, t *testing.T) {
	resetStore()
	oldAdmin := admin
	defer func() { admin = oldAdmin }()
	setCommitProofAdmin(cur)
	client := &mockClient{chainId: "union-1", status: types.StatusExpired}
	clientId := registerMockClient(client)

	uassert.AbortsContains(t, cur, "client is not active", func(cur realm) {
		CommitNonMembershipProof(cross(cur), types.MsgCommitNonMembershipProof{
			ClientId:    clientId,
			ProofHeight: 10,
			Proof:       types.Bytes("proof"),
			Path:        types.Bytes("path"),
		})
	})

	if len(client.nonMembershipKeys) != 0 {
		t.Fatalf("non-membership calls: got %d want 0", len(client.nonMembershipKeys))
	}
	if GetCommittedNonMembershipProof(clientId, 10, types.Bytes("path")) {
		t.Fatal("inactive client must not commit non-membership proof")
	}
}

// Union Sui reference:
// https://github.com/unionlabs/union/blob/d91c5e94354e15801bd5f82dc658eae3b79f2dad/sui/ibc/sources/ibc.move#L1730-L1755
func TestCommitPacketTimeoutRejectsBeforeTimeout(cur realm, t *testing.T) {
	resetStore()
	_, _, channelId := setupOpenChannel(t)
	client := mockClientFor(channelId)
	packet := types.Packet{
		SourceChannelId:      99,
		DestinationChannelId: channelId,
		Data:                 types.Bytes("transfer"),
		TimeoutTimestamp:     types.Timestamp(nowNanos() + 1_000_000_000),
	}

	uassert.AbortsContains(t, cur, "packet timeout not reached", func(cur realm) {
		CommitPacketTimeout(cur, types.MsgCommitPacketTimeout{
			Packet:      packet,
			ProofHeight: 10,
			Proof:       types.Bytes("packet-proof"),
		})
	})

	if len(client.membershipKeys) != 0 {
		t.Fatalf("membership calls: got %d want 0", len(client.membershipKeys))
	}
	if got := QueryPacketTimeout(packet); got != "" {
		t.Fatalf("early timeout must not commit packet timeout; got %q", got)
	}
}

func TestCommitPacketTimeoutRejectsAlreadyReceivedBeforeVerification(cur realm, t *testing.T) {
	resetStore()
	_, _, channelId := setupOpenChannel(t)
	client := mockClientFor(channelId)
	packet := types.Packet{
		SourceChannelId:      99,
		DestinationChannelId: channelId,
		Data:                 types.Bytes("transfer"),
		TimeoutTimestamp:     types.Timestamp(nowNanos() - 1),
	}
	store.setPacketReceipt(packet)

	uassert.AbortsContains(t, cur, "packet already received", func(cur realm) {
		CommitPacketTimeout(cur, types.MsgCommitPacketTimeout{
			Packet:      packet,
			ProofHeight: 10,
			Proof:       types.Bytes("packet-proof"),
		})
	})

	if len(client.membershipKeys) != 0 {
		t.Fatalf("membership calls: got %d want 0", len(client.membershipKeys))
	}
	if got := QueryPacketTimeout(packet); got != "" {
		t.Fatalf("received packet must not commit timeout; got %q", got)
	}
}

func TestCommitPacketTimeoutRejectsInactiveClientBeforeVerification(cur realm, t *testing.T) {
	resetStore()
	_, _, channelId := setupOpenChannel(t)
	client := mockClientFor(channelId)
	client.status = types.StatusFrozen
	packet := types.Packet{
		SourceChannelId:      99,
		DestinationChannelId: channelId,
		Data:                 types.Bytes("transfer"),
		TimeoutTimestamp:     types.Timestamp(nowNanos() - 1),
	}

	uassert.AbortsContains(t, cur, "client is not active", func(cur realm) {
		CommitPacketTimeout(cur, types.MsgCommitPacketTimeout{
			Packet:      packet,
			ProofHeight: 10,
			Proof:       types.Bytes("packet-proof"),
		})
	})

	if len(client.membershipKeys) != 0 {
		t.Fatalf("membership calls: got %d want 0", len(client.membershipKeys))
	}
	if got := QueryPacketTimeout(packet); got != "" {
		t.Fatalf("inactive client must not commit timeout; got %q", got)
	}
}

func TestCommitPacketTimeoutRejectsClosedChannelBeforeVerification(cur realm, t *testing.T) {
	resetStore()
	_, _, channelId := setupOpenChannel(t)
	client := mockClientFor(channelId)
	channel := store.getChannel(channelId)
	channel.State = types.ChannelStateClosed
	store.saveChannel(channelId, channel)
	packet := types.Packet{
		SourceChannelId:      99,
		DestinationChannelId: channelId,
		Data:                 types.Bytes("transfer"),
		TimeoutTimestamp:     types.Timestamp(nowNanos() - 1),
	}

	uassert.AbortsContains(t, cur, "invalid channel state", func(cur realm) {
		CommitPacketTimeout(cur, types.MsgCommitPacketTimeout{
			Packet:      packet,
			ProofHeight: 10,
			Proof:       types.Bytes("packet-proof"),
		})
	})

	if len(client.membershipKeys) != 0 {
		t.Fatalf("membership calls: got %d want 0", len(client.membershipKeys))
	}
	if got := QueryPacketTimeout(packet); got != "" {
		t.Fatalf("closed channel must not commit timeout; got %q", got)
	}
}

func TestCommitPacketTimeoutRejectsClosedConnectionBeforeVerification(cur realm, t *testing.T) {
	resetStore()
	_, connId, channelId := setupOpenChannel(t)
	client := mockClientFor(channelId)
	store.saveConnection(connId, types.Connection{
		State:                    types.ConnectionStateInit,
		ClientId:                 types.ClientId(1),
		CounterpartyClientId:     types.ClientId(99),
		CounterpartyConnectionId: types.ConnectionId(99),
	})
	packet := types.Packet{
		SourceChannelId:      99,
		DestinationChannelId: channelId,
		Data:                 types.Bytes("transfer"),
		TimeoutTimestamp:     types.Timestamp(nowNanos() - 1),
	}

	uassert.AbortsContains(t, cur, "invalid connection state", func(cur realm) {
		CommitPacketTimeout(cur, types.MsgCommitPacketTimeout{
			Packet:      packet,
			ProofHeight: 10,
			Proof:       types.Bytes("packet-proof"),
		})
	})

	if len(client.membershipKeys) != 0 {
		t.Fatalf("membership calls: got %d want 0", len(client.membershipKeys))
	}
	if got := QueryPacketTimeout(packet); got != "" {
		t.Fatalf("closed connection must not commit timeout; got %q", got)
	}
}

// Union Sui reference:
// https://github.com/unionlabs/union/blob/d91c5e94354e15801bd5f82dc658eae3b79f2dad/sui/ibc/sources/ibc.move#L1764-L1800
func TestCommitPacketTimeoutStoresTimeoutCommitment(cur realm, t *testing.T) {
	resetStore()
	_, _, channelId := setupOpenChannel(t)
	client := mockClientFor(channelId)
	packet := types.Packet{
		SourceChannelId:      99,
		DestinationChannelId: channelId,
		Data:                 types.Bytes("transfer"),
		TimeoutTimestamp:     types.Timestamp(nowNanos() - 1),
	}
	proof := types.Bytes("packet-proof")

	CommitPacketTimeout(cross(cur), types.MsgCommitPacketTimeout{
		Packet:      packet,
		ProofHeight: 10,
		Proof:       proof,
	})

	if len(client.membershipKeys) != 1 {
		t.Fatalf("membership calls: got %d want 1", len(client.membershipKeys))
	}
	packetPath := types.BatchPacketsPath(commitPacketHash(packet))
	if client.membershipHeights[0] != types.NewHeight(10) ||
		string(client.membershipProofs[0]) != string(proof) ||
		string(client.membershipKeys[0]) != string(packetPath[:]) ||
		string(client.membershipValues[0]) != string(types.COMMITMENT_MAGIC[:]) {
		t.Fatal("CommitPacketTimeout must verify source packet membership")
	}
	if got := QueryPacketTimeout(packet); got != types.COMMITMENT_MAGIC.String() {
		t.Fatalf("packet timeout commitment: got %q want %s", got, types.COMMITMENT_MAGIC)
	}
}
