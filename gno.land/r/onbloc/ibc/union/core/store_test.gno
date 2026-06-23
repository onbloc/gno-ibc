package core

import (
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/onbloc/ibc/union/types"
)

func TestStoreKeyHelpers(cur realm, t *testing.T) {
	exactCases := []struct {
		name string
		got  string
		want string
	}{
		{"port key", portKey(types.Bytes("port")), "port"},
	}

	var h256Key types.H256
	for i := 0; i < len(h256Key); i++ {
		h256Key[i] = byte(i)
	}
	exactCases = append(exactCases, struct {
		name string
		got  string
		want string
	}{
		name: "h256 chain param key",
		got:  h256ChainParamKey(h256Key),
		want: "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f",
	})

	for _, tc := range exactCases {
		t.Run(tc.name, func(t *testing.T) {
			if tc.got != tc.want {
				t.Fatalf("got %q want %q", tc.got, tc.want)
			}
		})
	}

	distinctCases := []struct {
		name  string
		left  string
		again string
		right string
	}{
		{"client key", clientKey(1), clientKey(1), clientKey(2)},
		{"connection key", connectionKey(1), connectionKey(1), connectionKey(2)},
		{"channel key", channelKey(1), channelKey(1), channelKey(2)},
	}

	for _, tc := range distinctCases {
		t.Run(tc.name, func(t *testing.T) {
			if tc.left == "" {
				t.Fatal("left key is empty")
			}
			if tc.left != tc.again {
				t.Fatal("key helper is not stable")
			}
			if tc.left == tc.right {
				t.Fatalf("keys for distinct ids collided: %q", tc.left)
			}
		})
	}
}

func TestClientStore(cur realm, t *testing.T) {
	cases := []struct {
		name string
		run  func(*testing.T)
	}{
		{"get unknown client", func(t *testing.T) {
			if store.getClient(types.ClientId(999)) != nil {
				t.Fatal("unknown client must return nil")
			}
		}},
		{"get stored client", func(t *testing.T) {
			added := addMockClient(&mockClient{})
			got := store.getClient(added.id)
			if got == nil {
				t.Fatal("stored client not found")
			}
			if got.id != added.id {
				t.Errorf("id: got %v want %v", got.id, added.id)
			}
		}},
		{"register client", func(t *testing.T) {
			lc := &mockClient{}

			store.registerClient(mockType, lc)
			if !store.hasRegisteredClient(mockType) {
				t.Fatal("registered client type not found")
			}
			got, ok := store.registeredClient(mockType)
			if !ok {
				t.Fatal("registered client lookup returned false")
			}
			if got != lc {
				t.Fatal("registered client lookup returned wrong light client")
			}
		}},
		{"register duplicate client panics", func(t *testing.T) {
			store.registerClient(mockType, &mockClient{})
			mustPanic(t, func() { store.registerClient(mockType, &mockClient{}) })
		}},
		{"add client", func(t *testing.T) {
			creator := testutils.TestAddress("creator")
			lc := &mockClient{}
			c := store.addClient(types.ClientId(7), mockType, creator, lc)

			if c.id != types.ClientId(7) || c.typ != mockType || c.creator != creator || c.lightClient != lc {
				t.Fatal("client fields not saved")
			}
			if got := store.getClient(types.ClientId(7)); got != c {
				t.Fatal("client not indexed by id")
			}
		}},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			resetStore(cur)
			tc.run(t)
		})
	}
}

func TestNextStoreIds(cur realm, t *testing.T) {
	cases := []struct {
		name string
		run  func(*testing.T)
	}{
		{"client id", func(t *testing.T) {
			first := store.nextClientId()
			second := store.nextClientId()
			if second != first+1 {
				t.Errorf("client IDs not sequential: got %v and %v", first, second)
			}
		}},
		{"connection id", func(t *testing.T) {
			first := store.nextConnectionId()
			second := store.nextConnectionId()
			if second != first+1 {
				t.Errorf("connection IDs not sequential: got %v and %v", first, second)
			}
		}},
		{"channel id", func(t *testing.T) {
			first := store.nextChannelId()
			second := store.nextChannelId()
			if second != first+1 {
				t.Errorf("channel IDs not sequential: got %v and %v", first, second)
			}
		}},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			resetStore(cur)
			tc.run(t)
		})
	}
}

func TestConnectionStore(cur realm, t *testing.T) {
	cases := []struct {
		name string
		run  func(*testing.T)
	}{
		{"save connection", func(t *testing.T) {
			clientId := registerMockClient(&mockClient{})
			conn := types.Connection{
				State:                    types.ConnectionStateOpen,
				ClientId:                 clientId,
				CounterpartyClientId:     types.ClientId(2),
				CounterpartyConnectionId: types.ConnectionId(99),
			}
			id := store.nextConnectionId()
			store.saveConnection(id, conn)

			got, ok := store.getConnection(id)
			if !ok {
				t.Fatal("connection not found")
			}
			if got.State != types.ConnectionStateOpen {
				t.Errorf("state: got %v want Open", got.State)
			}
			if got.ClientId != clientId {
				t.Errorf("clientId: got %v want %v", got.ClientId, clientId)
			}

			want := hexString(mustEncodeABI(conn.EncodeABI()))
			if got := QueryConnection(id); got != want {
				t.Errorf("QueryConnection: got %q want %q", got, want)
			}
		}},
		{"get unknown connection", func(t *testing.T) {
			if _, ok := store.getConnection(types.ConnectionId(999)); ok {
				t.Fatal("unknown connection must return false")
			}
		}},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			resetStore(cur)
			tc.run(t)
		})
	}
}

func TestChannelStore(cur realm, t *testing.T) {
	cases := []struct {
		name string
		run  func(*testing.T)
	}{
		{"create channel", func(t *testing.T) {
			connectionId := addMockConnection(types.ConnectionStateOpen)
			channelId := store.nextChannelId()
			portId := types.Bytes("gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm")
			counterpartyPortId := types.Bytes("counterparty")
			channel := types.Channel{
				State:              types.ChannelStateInit,
				ConnectionId:       connectionId,
				CounterpartyPortId: counterpartyPortId,
				Version:            "ucs03-zkgm-0",
			}

			store.createChannel(channelId, channel, portId)

			got := store.getChannel(channelId)
			if got.State != types.ChannelStateInit {
				t.Errorf("state: got %v want Init", got.State)
			}
			if string(store.getChannelOwner(channelId)) != string(portId) {
				t.Errorf("port owner: got %q want %q", string(store.getChannelOwner(channelId)), string(portId))
			}
			portId[0] = 'x'
			counterpartyPortId[0] = 'X'
			entry, ok := store.getChannelEntry(channelId)
			if !ok {
				t.Fatal("channel entry not found")
			}
			if string(entry.portId) != "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm" {
				t.Fatal("createChannel must clone owner port id")
			}
			if string(entry.channel.CounterpartyPortId) != "counterparty" {
				t.Fatal("createChannel must clone channel byte fields")
			}
		}},
		{"save channel", func(t *testing.T) {
			connectionId := addMockConnection(types.ConnectionStateOpen)
			id := store.nextChannelId()

			store.createChannel(id, types.Channel{State: types.ChannelStateInit, ConnectionId: connectionId}, nil)
			states := []struct {
				name  string
				state types.ChannelState
			}{
				{"try open", types.ChannelStateTryOpen},
				{"open", types.ChannelStateOpen},
				{"closed", types.ChannelStateClosed},
			}

			for _, state := range states {
				t.Run(state.name, func(t *testing.T) {
					store.saveChannel(id, types.Channel{State: state.state, ConnectionId: connectionId})
					if got := store.getChannel(id).State; got != state.state {
						t.Errorf("state: got %v want %v", got, state.state)
					}
				})
			}
		}},
		{"save unknown channel panics", func(t *testing.T) {
			mustPanic(t, func() { store.saveChannel(types.ChannelId(999), types.Channel{}) })
		}},
		{"get unknown channel panics", func(t *testing.T) {
			mustPanic(t, func() { store.getChannel(types.ChannelId(999)) })
		}},
		{"get unknown channel owner panics", func(t *testing.T) {
			mustPanic(t, func() { store.getChannelOwner(types.ChannelId(999)) })
		}},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			resetStore(cur)
			tc.run(t)
		})
	}
}

func TestPortStore(cur realm, t *testing.T) {
	cases := []struct {
		name string
		run  func(*testing.T)
	}{
		{"get app by port id", func(t *testing.T) {
			portId := types.Bytes("gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm")
			app := &mockApp{}
			store.ports[portKey(portId)] = app

			if got := store.getAppByPortId(portId); got != app {
				t.Fatal("getAppByPortId returned wrong app")
			}
		}},
		{"get missing app by port id panics", func(t *testing.T) {
			mustPanic(t, func() { store.getAppByPortId(types.Bytes("g1missing")) })
		}},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			resetStore(cur)
			tc.run(t)
		})
	}
}

func TestCommitmentStore(cur realm, t *testing.T) {
	cases := []struct {
		name string
		run  func(types.H256, types.H256)
	}{
		{"persistent commitment", func(path types.H256, value types.H256) {
			store.setCommitment(path, value)
		}},
		{"memory commitment", func(path types.H256, value types.H256) {
			store.setCommitmentMem(path, value)
		}},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			resetStore(cur)
			path := types.Keccak([]byte("path"))
			value := types.Keccak([]byte("value"))

			tc.run(path, value)
			got, ok := store.getCommitment(path)
			if !ok {
				t.Fatal("commitment not found")
			}
			if got != value {
				t.Errorf("commitment: got %s want %s", got.String(), value.String())
			}
		})
	}
}

func TestPacketCommitmentStore(cur realm, t *testing.T) {
	packet := types.NewPacket(1, 2, []byte("data"), 10)
	batchHash := CommitPacketsHash([]types.Packet{packet})
	batchValue := types.Keccak([]byte("batch-value"))

	cases := []struct {
		name string
		run  func(*testing.T)
	}{
		{"commit packet path", func(t *testing.T) {
			if store.HasPacketCommitment(packet) {
				t.Fatal("packet commitment must start missing")
			}

			store.CommitPacket(0, cur, packet)

			if !store.HasPacketCommitment(packet) {
				t.Fatal("packet commitment missing after CommitPacket")
			}
			if got, ok := store.PacketCommitment(1, packet); !ok || got != types.COMMITMENT_MAGIC {
				t.Fatal("PacketCommitment returned wrong value")
			}
			if got, ok := store.getCommitment(packetCommitmentPath(packet)); !ok || got != types.COMMITMENT_MAGIC {
				t.Fatal("CommitPacket stored the wrong packet commitment path")
			}
		}},
		{"acknowledged packet stays memory only", func(t *testing.T) {
			store.CommitPacket(0, cur, packet)
			store.SetPacketAcknowledged(0, cur, packet)

			if got, ok := store.PacketCommitment(1, packet); !ok || got != types.COMMITMENT_MAGIC_ACK {
				t.Fatal("SetPacketAcknowledged did not update memory commitment")
			}
			if got, ok := store.getCommitment(packetCommitmentPath(packet)); !ok || got != types.COMMITMENT_MAGIC_ACK {
				t.Fatal("SetPacketAcknowledged stored the wrong packet commitment path")
			}
		}},
		{"packet receipt and acknowledgement share ack path", func(t *testing.T) {
			if store.HasPacketReceipt(packet) {
				t.Fatal("packet receipt must start missing")
			}

			store.SetPacketReceipt(0, cur, packet)

			if !store.HasPacketReceipt(packet) {
				t.Fatal("packet receipt missing after SetPacketReceipt")
			}
			if got, ok := store.getCommitment(packetAcknowledgementPath(packet)); !ok || got != types.COMMITMENT_MAGIC {
				t.Fatal("SetPacketReceipt stored the wrong acknowledgement path")
			}

			store.CommitAcknowledgement(0, cur, packet, []byte("ack"))

			if got, ok := store.AcknowledgementReceipt(1, packet); !ok || got != types.CommitAcks([][]byte{[]byte("ack")}) {
				t.Fatal("AcknowledgementReceipt returned wrong value")
			}
			if got, ok := store.getCommitment(packetAcknowledgementPath(packet)); !ok || got != types.CommitAcks([][]byte{[]byte("ack")}) {
				t.Fatal("CommitAcknowledgement stored the wrong acknowledgement path")
			}
		}},
		{"batch packets path", func(t *testing.T) {
			store.SaveBatchPackets(0, cur, 1, batchHash, batchValue)

			if got, ok := store.BatchPacketsAt(batchHash); !ok || got != batchValue {
				t.Fatal("BatchPacketsAt returned wrong value")
			}
			if got, ok := store.getCommitment(types.BatchPacketsPath(batchHash)); !ok || got != batchValue {
				t.Fatal("SaveBatchPackets stored the wrong batch packet path")
			}
		}},
		{"batch receipts path", func(t *testing.T) {
			store.SaveBatchReceipts(0, cur, 1, batchHash, batchValue)

			if got, ok := store.BatchReceiptsAt(batchHash); !ok || got != batchValue {
				t.Fatal("BatchReceiptsAt returned wrong value")
			}
			if got, ok := store.getCommitment(types.BatchReceiptsPath(batchHash)); !ok || got != batchValue {
				t.Fatal("SaveBatchReceipts stored the wrong batch receipt path")
			}
		}},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			resetStore(cur)
			tc.run(t)
		})
	}
}

func TestClientByteStore(cur realm, t *testing.T) {
	cases := []struct {
		name string
		run  func(*testing.T)
	}{
		{"save client state", func(t *testing.T) {
			c := addMockClient(&mockClient{})
			in := []byte{1, 2, 3}

			c.saveClientState(in)
			in[0] = 9
			got, ok := store.ClientStateBytes(c.id)
			if !ok {
				t.Fatal("client state not found")
			}
			if string(got) != string([]byte{1, 2, 3}) {
				t.Errorf("client state: got %x want 010203", got)
			}
			got[0] = 8
			got2, _ := store.ClientStateBytes(c.id)
			if got2[0] != 1 {
				t.Fatal("ClientStateBytes must return a clone")
			}
		}},
		{"save consensus state", func(t *testing.T) {
			c := addMockClient(&mockClient{})
			height := types.NewHeight(10)
			in := []byte{4, 5, 6}

			c.saveConsensusState(height, in)
			in[0] = 9
			got, ok := c.getConsensusState(height)
			if !ok {
				t.Fatal("consensus state not found")
			}
			if string(got) != string([]byte{4, 5, 6}) {
				t.Errorf("consensus state: got %x want 040506", got)
			}
			got[0] = 8
			got2, _ := c.getConsensusState(height)
			if got2[0] != 4 {
				t.Fatal("getConsensusState must return a clone")
			}
		}},
		{"save client store", func(t *testing.T) {
			c := addMockClient(&mockClient{})
			in := []byte{7, 8, 9}

			c.saveClientStore("key", in)
			in[0] = 1
			got, ok := c.getClientStore("key")
			if !ok {
				t.Fatal("client store value not found")
			}
			if string(got) != string([]byte{7, 8, 9}) {
				t.Errorf("client store: got %x want 070809", got)
			}
			got[0] = 2
			got2, _ := c.getClientStore("key")
			if got2[0] != 7 {
				t.Fatal("getClientStore must return a clone")
			}
		}},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			resetStore(cur)
			tc.run(t)
		})
	}
}

func TestProofStore(cur realm, t *testing.T) {
	cases := []struct {
		name string
		run  func(*testing.T)
	}{
		{"save membership proof", func(t *testing.T) {
			clientId := types.ClientId(1)
			path := []byte("proof-path")
			value := types.Keccak([]byte("proof-value"))

			store.saveMembershipProof(clientId, 42, path, value)
			got, ok := store.getMembershipProof(clientId, 42, path)
			if !ok {
				t.Fatal("membership proof not found")
			}
			if got != value {
				t.Errorf("membership proof: got %s want %s", got.String(), value.String())
			}
		}},
		{"save non-membership proof", func(t *testing.T) {
			clientId := types.ClientId(1)
			path := []byte("proof-path")

			store.saveNonMembershipProof(clientId, 42, path, types.NON_MEMBERSHIP_COMMITMENT_VALUE)
			if !store.hasNonMembershipProof(clientId, 42, path) {
				t.Fatal("non-membership proof not found")
			}
		}},
		{"non-membership proof requires sentinel value", func(t *testing.T) {
			clientId := types.ClientId(1)
			path := []byte("proof-path")

			store.saveNonMembershipProof(clientId, 43, path, types.Keccak([]byte("wrong-value")))
			if store.hasNonMembershipProof(clientId, 43, path) {
				t.Fatal("non-membership proof must require sentinel value")
			}
		}},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			resetStore(cur)
			tc.run(t)
		})
	}
}
