package transfer

// In-package replacement for the old send_callback_ack_ok/error scenario
// filetests: same-realm App{} allocation is legal here, so
// OnAcknowledgementPacket can be called directly with no test-only export.
//
// testing.SetRealm impersonates a distinct realm for the sender role
// (standing in for a real adapter like ics20zkgmadapter), since escrowing to
// transfer from transfer itself would be a same-address transfer.

import (
	"testing"
	"time"

	tmtesting "gno.land/p/aib/ibc/lightclient/tendermint/testing"
	"gno.land/p/aib/ibc/types"
	"gno.land/p/demo/tokens/grc20"
	"gno.land/p/nt/uassert/v0"
	"gno.land/p/nt/urequire/v0"
	"gno.land/r/demo/defi/grc20reg"

	"chain"
	"chain/runtime/unsafe"

	"gno.land/r/aib/ibc/core"
)

const transferPkgPath = "gno.land/r/aib/ibc/apps/transfer"

type mockSendCallbackTest struct {
	calls   int
	corrID  string
	success bool
}

func (m *mockSendCallbackTest) OnTransferSendResult(cur realm, corrID string, success bool, ack []byte) error {
	m.calls++
	m.corrID = corrID
	m.success = success
	return nil
}

// mockForwardHandlerTest is a trivial ForwardHandler, needed only to satisfy
// TransferWithCallback's registered-handler authorization check.
type mockForwardHandlerTest struct{}

func (mockForwardHandlerTest) Prepare(cur realm, req Request) error { return nil }
func (mockForwardHandlerTest) Execute(cur realm, req Request)       {}

func TestOnAcknowledgementPacket_SendCallback_Success(cur realm, t *testing.T) {
	SetAdmin(cross(cur), unsafe.OriginCaller())

	// Impersonate the registered handler's realm (distinct from transfer
	// itself) for the sender role.
	testing.SetRealm(testing.NewCodeRealm(transferPkgPath + "/testhandler_ok"))
	RegisterForwardHandler(cross(cur), mockForwardHandlerTest{})

	token, ledger := grc20.NewToken("Reverse GRC20 OK", "RGRCOK", 6, 0, cur)
	denom := grc20reg.Register(cross(cur), token, "reverse-send-ok-unit")
	urequire.NoError(t, ledger.Mint(cur.Address(), 100))
	urequire.NoError(t, token.RealmTeller(0, cur).Approve(0, cur, chain.PackageAddress(transferPkgPath), 40))

	clientID := core.CreateClient(cross(cur),
		tmtesting.NewClientState("chainA-2", types.NewHeight(2, 2)),
		tmtesting.GenConsensusState(time.Now(), []byte("apphash"), tmtesting.GenValset().Hash()),
	)
	core.RegisterCounterparty(cross(cur), clientID, [][]byte{[]byte("iavlStoreKey"), []byte("prefix-ok")}, "07-tendermint-100")

	callback := &mockSendCallbackTest{}
	packet, sequence := TransferWithCallback(cross(cur), clientID, "atone1receiver", denom, 40, uint64(time.Now().Add(time.Hour).Unix()), "", "corr-ok", callback)
	uassert.Equal(t, int64(60), token.BalanceOf(cur.Address()))

	ack := types.NewResultAppAcknowledgement([]byte{byte(1)})
	app := &App{}
	urequire.NoError(t, app.OnAcknowledgementPacket(cross(cur), clientID, "07-tendermint-100", sequence, ack.MarshalJSON(), packet.Payloads[0]))

	uassert.Equal(t, 1, callback.calls)
	uassert.Equal(t, "corr-ok", callback.corrID)
	uassert.True(t, callback.success)
	// Success ack: no refund, escrow stays put.
	uassert.Equal(t, int64(60), token.BalanceOf(cur.Address()))
}

func TestOnAcknowledgementPacket_SendCallback_Failure(cur realm, t *testing.T) {
	SetAdmin(cross(cur), unsafe.OriginCaller())

	testing.SetRealm(testing.NewCodeRealm(transferPkgPath + "/testhandler_fail"))
	RegisterForwardHandler(cross(cur), mockForwardHandlerTest{})

	token, ledger := grc20.NewToken("Reverse GRC20 Fail", "RGRCFAIL", 6, 0, cur)
	denom := grc20reg.Register(cross(cur), token, "reverse-send-fail-unit")
	urequire.NoError(t, ledger.Mint(cur.Address(), 100))
	urequire.NoError(t, token.RealmTeller(0, cur).Approve(0, cur, chain.PackageAddress(transferPkgPath), 40))

	clientID := core.CreateClient(cross(cur),
		tmtesting.NewClientState("chainA-2", types.NewHeight(2, 2)),
		tmtesting.GenConsensusState(time.Now(), []byte("apphash"), tmtesting.GenValset().Hash()),
	)
	core.RegisterCounterparty(cross(cur), clientID, [][]byte{[]byte("iavlStoreKey"), []byte("prefix-fail")}, "07-tendermint-101")

	callback := &mockSendCallbackTest{}
	packet, sequence := TransferWithCallback(cross(cur), clientID, "atone1receiver", denom, 40, uint64(time.Now().Add(time.Hour).Unix()), "", "corr-fail", callback)
	uassert.Equal(t, int64(60), token.BalanceOf(cur.Address()))

	app := &App{}
	urequire.NoError(t, app.OnAcknowledgementPacket(cross(cur), clientID, "07-tendermint-101", sequence, types.UniversalErrorAcknowledgement(), packet.Payloads[0]))

	uassert.Equal(t, 1, callback.calls)
	uassert.Equal(t, "corr-fail", callback.corrID)
	uassert.False(t, callback.success)
	// Failure ack: escrow refunds back to the sender.
	uassert.Equal(t, int64(100), token.BalanceOf(cur.Address()))
}
