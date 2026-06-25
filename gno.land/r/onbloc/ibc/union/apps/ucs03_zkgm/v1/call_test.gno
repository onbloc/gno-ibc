package impl

import (
	"bytes"
	"testing"

	types "gno.land/p/onbloc/ibc/union/types"

	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/uassert/v0"
	z "gno.land/p/onbloc/ibc/union/zkgm"
	core "gno.land/r/onbloc/ibc/union/core"
)

// mockReceiverPath is the registry key the dispatch tests register the inline
// mock receiver under (see mock_receiver_test.gno). It is a stable identifier,
// not a deployed realm path.
const mockReceiverPath = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/mock"

func TestExecuteCall(cur realm, t *testing.T) {
	packet := core.NewPacket(types.ChannelId(7), types.ChannelId(8), nil, 0)
	path := u256.NewUint(9)

	cases := []struct {
		name             string
		call             z.Call
		intent           bool
		relayer          address
		relayerMsg       []byte
		setup            func()
		wantStatus       types.PacketStatus
		wantFailureInner string
		wantOnlyMaker    bool
		wantCalls        int
		wantIntentCalls  int
		assertions       func(res types.RecvPacketResult)
	}{
		{
			name: "dispatch OnZkgm callback",
			call: z.Call{
				Sender:           []byte("sender"),
				ContractAddress:  []byte(mockReceiverPath),
				ContractCalldata: []byte("calldata"),
			},
			relayer:    address("g1relayer"),
			relayerMsg: []byte("relay-msg"),
			setup: func() {
				testStore.SetReceiver(0, cur, mockReceiverPath, Zkgmable(cross(cur)))
			},
			wantStatus:      types.PacketStatusSuccess,
			wantCalls:       1,
			wantIntentCalls: 0,
			assertions: func(res types.RecvPacketResult) {
				ack, err := z.DecodeAck(res.Acknowledgement)
				uassert.NoError(t, err)
				uassert.True(t, ack.Tag.Eq(tagAckSuccess()))
				uassert.Equal(t, "7", LastSourceChannel(cross(cur)))
				uassert.Equal(t, "8", LastDestinationChannel(cross(cur)))
				uassert.Equal(t, "sender", LastSender(cross(cur)))
				uassert.Equal(t, "calldata", LastCalldata(cross(cur)))
				uassert.Equal(t, "g1relayer", LastCaller(cross(cur)))
				uassert.Equal(t, "g1relayer", LastRelayer(cross(cur)))
				uassert.Equal(t, "relay-msg", LastRelayerMsg(cross(cur)))
				uassert.Equal(t, "9", LastPathDec(cross(cur)))
				uassert.Equal(t, z.PredictCallProxyAccount(path, types.ChannelId(8), []byte("sender")), LastProxyAccount(cross(cur)))
			},
		},
		{
			name: "dispatch OnIntentZkgm callback",
			call: z.Call{
				Sender:           []byte("sender"),
				ContractAddress:  []byte(mockReceiverPath),
				ContractCalldata: []byte("calldata"),
			},
			intent:     true,
			relayer:    address("g1maker"),
			relayerMsg: []byte("mm-msg"),
			setup: func() {
				testStore.SetReceiver(0, cur, mockReceiverPath, Zkgmable(cross(cur)))
			},
			wantStatus:      types.PacketStatusSuccess,
			wantCalls:       0,
			wantIntentCalls: 1,
			assertions: func(res types.RecvPacketResult) {
				ack, err := z.DecodeAck(res.Acknowledgement)
				uassert.NoError(t, err)
				uassert.True(t, ack.Tag.Eq(tagAckSuccess()))
				uassert.Equal(t, "calldata", LastIntentCalldata(cross(cur)))
				uassert.Equal(t, "g1maker", LastIntentMarketMaker(cross(cur)))
			},
		},
		{
			name: "receiver error returns failure ack",
			call: z.Call{
				Sender:          []byte("sender"),
				ContractAddress: []byte(mockReceiverPath),
			},
			relayer: address("g1relayer"),
			setup: func() {
				testStore.SetReceiver(0, cur, mockReceiverPath, Zkgmable(cross(cur)))
				SetError(cross(cur), "receiver failed")
			},
			wantStatus:       types.PacketStatusFailure,
			wantFailureInner: "receiver failed",
		},
		{
			name: "receiver panic returns only-maker ack",
			call: z.Call{
				Sender:          []byte("sender"),
				ContractAddress: []byte(mockReceiverPath),
			},
			relayer: address("g1relayer"),
			setup: func() {
				testStore.SetReceiver(0, cur, mockReceiverPath, Zkgmable(cross(cur)))
				SetPanic(cross(cur), "boom")
			},
			wantStatus:    types.PacketStatusSuccess,
			wantOnlyMaker: true,
		},
		{
			name: "eureka returns failure ack",
			call: z.Call{
				Eureka:          true,
				Sender:          []byte("sender"),
				ContractAddress: []byte(mockReceiverPath),
			},
			relayer:          address("g1relayer"),
			wantStatus:       types.PacketStatusFailure,
			wantFailureInner: "eureka mode not supported",
		},
		{
			name: "missing receiver returns failure ack",
			call: z.Call{
				Sender:          []byte("sender"),
				ContractAddress: []byte("gno.land/r/missing/zkgm/receiver"),
			},
			relayer:          address("g1relayer"),
			wantStatus:       types.PacketStatusFailure,
			wantFailureInner: "receiver not registered, gno.land/r/missing/zkgm/receiver",
		},
		{
			name: "intent receiver error returns only-maker ack",
			call: z.Call{
				Sender:          []byte("sender"),
				ContractAddress: []byte(mockReceiverPath),
			},
			intent:  true,
			relayer: address("g1relayer"),
			setup: func() {
				testStore.SetReceiver(0, cur, mockReceiverPath, Zkgmable(cross(cur)))
				SetError(cross(cur), "intent receiver failed")
			},
			wantStatus:    types.PacketStatusSuccess,
			wantOnlyMaker: true,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			Reset(cross(cur))
			if tc.setup != nil {
				tc.setup()
			}

			res, err := newTestImpl().executeCall(0, cur, packet, tc.relayer, tc.relayerMsg, path, tc.call, tc.intent)
			uassert.NoError(t, err)
			uassert.True(t, res.Status == tc.wantStatus)

			if tc.wantOnlyMaker {
				uassert.True(t, bytes.Equal(z.ACK_ERR_ONLY_MAKER, res.Acknowledgement))
				return
			}

			if tc.wantFailureInner != "" {
				ack, err := z.DecodeAck(res.Acknowledgement)
				uassert.NoError(t, err)
				uassert.True(t, ack.Tag.Eq(tagAckFailure()))
				uassert.Equal(t, tc.wantFailureInner, string(ack.InnerAck))
				return
			}

			uassert.Equal(t, tc.wantCalls, Calls(cross(cur)))
			uassert.Equal(t, tc.wantIntentCalls, IntentCalls(cross(cur)))
			if tc.assertions != nil {
				tc.assertions(res)
			}
		})
	}
}

func TestIntentRecvOnlyMakerCallAborts(cur realm, t *testing.T) {
	Reset(cross(cur))
	testStore.SetReceiver(0, cur, mockReceiverPath, Zkgmable(cross(cur)))
	SetPanic(cross(cur), "boom")
	data := mustZkgmPacketBytes(batchMustCallInstruction(z.Call{
		Sender:          []byte("sender"),
		ContractAddress: []byte(mockReceiverPath),
	}))
	packet := core.NewPacket(types.ChannelId(7), types.ChannelId(8), data, 0)

	uassert.AbortsContains(t, cur, "only maker", func(cur realm) {
		newTestImpl().OnIntentRecvPacket(0, cur, packet, address("g1relayer"), nil)
	})
}

func TestVerifyCallRejectsInvalidSender(cur realm, t *testing.T) {
	err := newTestImpl().verifyCall(0, cur, z.Call{
		Sender: []byte("other"),
	})

	uassert.ErrorContains(t, err, "invalid call sender")
}

func TestCallSuccessAck(cur realm, t *testing.T) {
	res, err := callSuccessAck()

	uassert.NoError(t, err)
	uassert.True(t, res.Status == types.PacketStatusSuccess)

	ack, err := z.DecodeAck(res.Acknowledgement)
	uassert.NoError(t, err)
	uassert.True(t, ack.Tag.Eq(tagAckSuccess()))
	uassert.True(t, len(ack.InnerAck) == 0)
}

func TestCanRevive(cur realm, t *testing.T) {
	uassert.True(t, canRevive())
}

func TestCallErrAck(cur realm, t *testing.T) {
	res := callErrAck(0, cur, makeError("receiver failed"))

	uassert.True(t, res.Status == types.PacketStatusFailure)
	ack, err := z.DecodeAck(res.Acknowledgement)
	uassert.NoError(t, err)
	uassert.True(t, ack.Tag.Eq(tagAckFailure()))
	uassert.Equal(t, "receiver failed", string(ack.InnerAck))
}

func TestAcknowledgeCall(cur realm, t *testing.T) {
	packet := core.NewPacket(types.ChannelId(1), types.ChannelId(2), nil, 0)

	cases := []struct {
		name    string
		call    z.Call
		wantErr string
	}{
		{
			name:    "standard call returns nil",
			call:    z.Call{Sender: []byte("sender")},
			wantErr: "",
		},
		{
			name:    "eureka returns error",
			call:    z.Call{Eureka: true},
			wantErr: "eureka mode not supported",
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			err := newTestImpl().acknowledgeCall(0, cur, packet, u256.Zero(), tc.call)
			if tc.wantErr != "" {
				uassert.ErrorContains(t, err, tc.wantErr)
				return
			}
			uassert.NoError(t, err)
		})
	}
}

func TestTimeoutCall(cur realm, t *testing.T) {
	packet := core.NewPacket(types.ChannelId(1), types.ChannelId(2), nil, 0)

	cases := []struct {
		name    string
		call    z.Call
		wantErr string
	}{
		{
			name:    "standard call returns nil",
			call:    z.Call{Sender: []byte("sender")},
			wantErr: "",
		},
		{
			name:    "eureka returns error",
			call:    z.Call{Eureka: true},
			wantErr: "eureka mode not supported",
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			err := newTestImpl().timeoutCall(0, cur, packet, u256.Zero(), tc.call)
			if tc.wantErr != "" {
				uassert.ErrorContains(t, err, tc.wantErr)
				return
			}
			uassert.NoError(t, err)
		})
	}
}

func TestSafeCallOnZkgm(cur realm, t *testing.T) {
	Reset(cross(cur))
	testStore.SetReceiver(0, cur, mockReceiverPath, Zkgmable(cross(cur)))
	receiver := Zkgmable(cross(cur))
	env := z.CallEnv{Caller: "relayer"}

	cases := []struct {
		name         string
		setup        func()
		wantErr      bool
		wantPanicked bool
	}{
		{
			name:         "receiver success returns nil no-panic",
			wantErr:      false,
			wantPanicked: false,
		},
		{
			name: "receiver error returns error no-panic",
			setup: func() {
				SetError(cross(cur), "call failed")
			},
			wantErr:      true,
			wantPanicked: false,
		},
		{
			name: "receiver panic returns nil panicked",
			setup: func() {
				SetPanic(cross(cur), "boom")
			},
			wantErr:      false,
			wantPanicked: true,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			Reset(cross(cur))
			testStore.SetReceiver(0, cur, mockReceiverPath, Zkgmable(cross(cur)))
			if tc.setup != nil {
				tc.setup()
			}

			err, panicked := safeCallOnZkgm(0, cur, receiver, env)
			uassert.Equal(t, tc.wantPanicked, panicked)
			if tc.wantErr {
				uassert.ErrorContains(t, err, "call failed")
				return
			}
			uassert.NoError(t, err)
		})
	}
}

func TestSafeCallOnIntentZkgm(cur realm, t *testing.T) {
	Reset(cross(cur))
	testStore.SetReceiver(0, cur, mockReceiverPath, Zkgmable(cross(cur)))
	receiver := Zkgmable(cross(cur))
	env := z.IntentCallEnv{Caller: "maker"}

	cases := []struct {
		name         string
		setup        func()
		wantErr      bool
		wantPanicked bool
	}{
		{
			name:         "receiver success returns nil no-panic",
			wantErr:      false,
			wantPanicked: false,
		},
		{
			name: "receiver error returns error no-panic",
			setup: func() {
				SetError(cross(cur), "intent failed")
			},
			wantErr:      true,
			wantPanicked: false,
		},
		{
			name: "receiver panic returns nil panicked",
			setup: func() {
				SetPanic(cross(cur), "intent boom")
			},
			wantErr:      false,
			wantPanicked: true,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			Reset(cross(cur))
			testStore.SetReceiver(0, cur, mockReceiverPath, Zkgmable(cross(cur)))
			if tc.setup != nil {
				tc.setup()
			}

			err, panicked := safeCallOnIntentZkgm(0, cur, receiver, env)
			uassert.Equal(t, tc.wantPanicked, panicked)
			if tc.wantErr {
				uassert.ErrorContains(t, err, "intent failed")
				return
			}
			uassert.NoError(t, err)
		})
	}
}
