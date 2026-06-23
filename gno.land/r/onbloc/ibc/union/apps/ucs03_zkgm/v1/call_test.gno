package impl

import (
	"bytes"
	"testing"

	types "gno.land/p/onbloc/ibc/union/types"

	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/uassert/v0"
	z "gno.land/p/onbloc/ibc/union/zkgm"
	"gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/mock"
	core "gno.land/r/onbloc/ibc/union/core"
)

const mockReceiverPath = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/mock"

func TestCallSuccessAck(t *testing.T) {
	res, err := callSuccessAck()

	uassert.NoError(t, err)
	uassert.True(t, res.Status == types.PacketStatusSuccess)
	ack, err := z.DecodeAck(res.Acknowledgement)
	uassert.NoError(t, err)
	uassert.True(t, ack.Tag.Eq(tagAckSuccess()))
	uassert.Equal(t, "", string(ack.InnerAck))
}

func TestAcknowledgeCall(cur realm, t *testing.T) {
	v := newTestImpl()
	packet := core.NewPacket(types.ChannelId(1), types.ChannelId(2), nil, 0)

	cases := []struct {
		name    string
		call    z.Call
		wantErr string
	}{
		{"standard call", z.Call{}, ""},
		{"eureka unsupported", z.Call{Eureka: true}, "eureka mode not supported"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			err := v.acknowledgeCall(0, cur, packet, u256.Zero(), tc.call)
			if tc.wantErr != "" {
				uassert.ErrorContains(t, err, tc.wantErr)
				return
			}
			uassert.NoError(t, err)
		})
	}
}

func TestTimeoutCall(cur realm, t *testing.T) {
	v := newTestImpl()
	packet := core.NewPacket(types.ChannelId(1), types.ChannelId(2), nil, 0)

	cases := []struct {
		name    string
		call    z.Call
		wantErr string
	}{
		{"standard call", z.Call{}, ""},
		{"eureka unsupported", z.Call{Eureka: true}, "eureka mode not supported"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			err := v.timeoutCall(0, cur, packet, u256.Zero(), tc.call)
			if tc.wantErr != "" {
				uassert.ErrorContains(t, err, tc.wantErr)
				return
			}
			uassert.NoError(t, err)
		})
	}
}

func TestCallErrAck(cur realm, t *testing.T) {
	res := callErrAck(0, cur, errInvalidCallSender)

	uassert.True(t, res.Status == types.PacketStatusFailure)
	ack, err := z.DecodeAck(res.Acknowledgement)
	uassert.NoError(t, err)
	uassert.True(t, ack.Tag.Eq(tagAckFailure()))
	uassert.Equal(t, errInvalidCallSender.Error(), string(ack.InnerAck))
}

func TestSafeCallOnZkgm(cur realm, t *testing.T) {
	cases := []struct {
		name        string
		err         string
		panicMsg    string
		wantErr     string
		wantPaniced bool
	}{
		{"success", "", "", "", false},
		{"receiver error", "receiver failed", "", "receiver failed", false},
		{"receiver panic", "", "boom", "", true},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			mock.Reset(cross(cur))
			if tc.err != "" {
				mock.SetError(cross(cur), tc.err)
			}
			if tc.panicMsg != "" {
				mock.SetPanic(cross(cur), tc.panicMsg)
			}

			err, panicked := safeCallOnZkgm(0, cur, mock.Zkgmable(cross(cur)), z.CallEnv{})

			uassert.Equal(t, tc.wantPaniced, panicked)
			if tc.wantErr != "" {
				uassert.ErrorContains(t, err, tc.wantErr)
				return
			}
			uassert.NoError(t, err)
		})
	}
}

func TestSafeCallOnIntentZkgm(cur realm, t *testing.T) {
	cases := []struct {
		name        string
		err         string
		panicMsg    string
		wantErr     string
		wantPaniced bool
	}{
		{"success", "", "", "", false},
		{"receiver error", "intent failed", "", "intent failed", false},
		{"receiver panic", "", "intent boom", "", true},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			mock.Reset(cross(cur))
			if tc.err != "" {
				mock.SetError(cross(cur), tc.err)
			}
			if tc.panicMsg != "" {
				mock.SetPanic(cross(cur), tc.panicMsg)
			}

			err, panicked := safeCallOnIntentZkgm(0, cur, mock.Zkgmable(cross(cur)), z.IntentCallEnv{})

			uassert.Equal(t, tc.wantPaniced, panicked)
			if tc.wantErr != "" {
				uassert.ErrorContains(t, err, tc.wantErr)
				return
			}
			uassert.NoError(t, err)
		})
	}
}

func TestExecuteCall(cur realm, t *testing.T) {
	type envExpectation struct {
		calls              int
		intentCalls        int
		sourceChannel      string
		destinationChannel string
		sender             string
		calldata           string
		caller             string
		relayer            string
		relayerMsg         string
		path               string
		proxyAccount       string
		intentMarketMaker  string
	}

	defaultCall := z.Call{
		Sender:           []byte("sender"),
		ContractAddress:  []byte(mockReceiverPath),
		ContractCalldata: []byte("calldata"),
	}

	cases := []struct {
		name           string
		intent         bool
		relayer        address
		relayerMsg     []byte
		path           *u256.Uint
		call           z.Call
		mockErr        string
		mockPanic      string
		wantStatus     types.PacketStatus
		wantAckSuccess bool
		wantAckFailure string
		wantOnlyMaker  bool
		checkEnv       bool
		wantEnv        envExpectation
	}{
		{
			name:           "dispatches on zkgm",
			relayer:        address("g1relayer"),
			relayerMsg:     []byte("relay-msg"),
			path:           u256.NewUint(9),
			call:           defaultCall,
			wantStatus:     types.PacketStatusSuccess,
			wantAckSuccess: true,
			checkEnv:       true,
			wantEnv: envExpectation{
				calls:              1,
				sourceChannel:      "7",
				destinationChannel: "8",
				sender:             "sender",
				calldata:           "calldata",
				caller:             "g1relayer",
				relayer:            "g1relayer",
				relayerMsg:         "relay-msg",
				path:               "9",
				proxyAccount:       PredictCallProxyAccount(u256.NewUint(9), types.ChannelId(8), []byte("sender")),
			},
		},
		{
			name:           "receiver error returns failure ack",
			relayer:        address("g1relayer"),
			path:           u256.Zero(),
			call:           defaultCall,
			mockErr:        "receiver failed",
			wantStatus:     types.PacketStatusFailure,
			wantAckFailure: "receiver failed",
		},
		{
			name:          "receiver panic returns only maker ack",
			relayer:       address("g1relayer"),
			path:          u256.Zero(),
			call:          defaultCall,
			mockPanic:     "boom",
			wantStatus:    types.PacketStatusSuccess,
			wantOnlyMaker: true,
		},
		{
			name:           "intent dispatches on intent zkgm",
			intent:         true,
			relayer:        address("g1maker"),
			relayerMsg:     []byte("mm-msg"),
			path:           u256.NewUint(9),
			call:           defaultCall,
			wantStatus:     types.PacketStatusSuccess,
			wantAckSuccess: true,
			checkEnv:       true,
			wantEnv: envExpectation{
				intentCalls:       1,
				calldata:          "calldata",
				intentMarketMaker: "g1maker",
			},
		},
	}

	for _, tc := range cases {
		mock.Reset(cross(cur))
		testStore = newMockStore()
		testStore.SetReceiver(0, cur, mockReceiverPath, mock.Zkgmable(cross(cur)))
		if tc.mockErr != "" {
			mock.SetError(cross(cur), tc.mockErr)
		}
		if tc.mockPanic != "" {
			mock.SetPanic(cross(cur), tc.mockPanic)
		}
		packet := core.NewPacket(types.ChannelId(7), types.ChannelId(8), nil, 0)

		res, err := newTestImpl().executeCall(0, cur, packet, tc.relayer, tc.relayerMsg, tc.path, tc.call, tc.intent)

		uassert.NoError(t, err)
		uassert.True(t, res.Status == tc.wantStatus)
		if tc.wantOnlyMaker {
			uassert.True(t, bytes.Equal(z.ACK_ERR_ONLY_MAKER, res.Acknowledgement))
			continue
		}

		ack, err := z.DecodeAck(res.Acknowledgement)
		uassert.NoError(t, err)
		if tc.wantAckSuccess {
			uassert.True(t, ack.Tag.Eq(tagAckSuccess()))
		}
		if tc.wantAckFailure != "" {
			uassert.True(t, ack.Tag.Eq(tagAckFailure()))
			uassert.Equal(t, tc.wantAckFailure, string(ack.InnerAck))
		}

		if !tc.checkEnv {
			continue
		}

		uassert.Equal(t, tc.wantEnv.calls, mock.Calls(cross(cur)))
		uassert.Equal(t, tc.wantEnv.intentCalls, mock.IntentCalls(cross(cur)))
		if tc.wantEnv.sourceChannel != "" {
			uassert.Equal(t, tc.wantEnv.sourceChannel, mock.LastSourceChannel(cross(cur)))
			uassert.Equal(t, tc.wantEnv.destinationChannel, mock.LastDestinationChannel(cross(cur)))
			uassert.Equal(t, tc.wantEnv.sender, mock.LastSender(cross(cur)))
			uassert.Equal(t, tc.wantEnv.calldata, mock.LastCalldata(cross(cur)))
			uassert.Equal(t, tc.wantEnv.caller, mock.LastCaller(cross(cur)))
			uassert.Equal(t, tc.wantEnv.relayer, mock.LastRelayer(cross(cur)))
			uassert.Equal(t, tc.wantEnv.relayerMsg, mock.LastRelayerMsg(cross(cur)))
			uassert.Equal(t, tc.wantEnv.path, mock.LastPathDec(cross(cur)))
			uassert.Equal(t, tc.wantEnv.proxyAccount, mock.LastProxyAccount(cross(cur)))
		}
		if tc.wantEnv.intentMarketMaker != "" {
			uassert.Equal(t, tc.wantEnv.calldata, mock.LastIntentCalldata(cross(cur)))
			uassert.Equal(t, tc.wantEnv.intentMarketMaker, mock.LastIntentMarketMaker(cross(cur)))
		}
	}
}

func TestIntentRecvOnlyMakerCallAborts(cur realm, t *testing.T) {
	mock.Reset(cross(cur))
	testStore.SetReceiver(0, cur, mockReceiverPath, mock.Zkgmable(cross(cur)))
	mock.SetPanic(cross(cur), "boom")
	data := mustZkgmPacketBytes(batchMustCallInstruction(z.Call{
		Sender:          []byte("sender"),
		ContractAddress: []byte(mockReceiverPath),
	}))
	packet := core.NewPacket(types.ChannelId(7), types.ChannelId(8), data, 0)

	uassert.AbortsContains(t, cur, "zkgm: only maker", func(cur realm) {
		newTestImpl().OnIntentRecvPacket(0, cur, packet, address("g1relayer"), nil)
	})
}

func TestVerifyCallRejectsInvalidSender(cur realm, t *testing.T) {
	err := newTestImpl().verifyCall(0, cur, z.Call{
		Sender: []byte("other"),
	})

	uassert.ErrorContains(t, err, "invalid call sender")
}
