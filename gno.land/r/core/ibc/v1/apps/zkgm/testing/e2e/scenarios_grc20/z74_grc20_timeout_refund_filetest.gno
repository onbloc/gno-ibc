// PKGPATH: gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/e2e/scenarios_grc20
package scenarios_grc20

import (
	stdtesting "testing"

	"gno.land/p/demo/tokens/grc20"
	"gno.land/p/nt/testutils/v0"

	u256 "gno.land/p/gnoswap/uint256"
	z "gno.land/p/onbloc/unionibc/zkgm"

	"gno.land/r/demo/defi/grc20reg"

	"gno.land/r/onbloc/unionibc/v1/apps/zkgm"
	"gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/e2e"
	"gno.land/r/onbloc/unionibc/v1/apps/zkgm/v0/impl"
	"gno.land/r/onbloc/unionibc/v1/core"

	_ "gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/loader"
)

const (
	timeoutClientType = core.ClientType("gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/e2e/scenarios_grc20/timeout")
	timeoutPkgPath    = "gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/e2e/scenarios_grc20"
)

type timeoutLightClient struct{}

func (m *timeoutLightClient) CreateClient(_ realm, clientId core.ClientId, clientStateBytes, consensusStateBytes []byte) string {
	return "grc20-timeout-chain"
}

func (m *timeoutLightClient) UpdateClient(cur realm, clientId core.ClientId, clientMessage []byte) core.ConsensusStateUpdate {
	return core.NewConsensusStateUpdate(cross(cur), core.Height(1), clientMessage, clientMessage)
}

func (m *timeoutLightClient) VerifyMembership(clientId core.ClientId, height core.Height, proof []byte, key []byte, value []byte) {
}

func (m *timeoutLightClient) VerifyNonMembership(clientId core.ClientId, height core.Height, proof []byte, key []byte) {
}

func (m *timeoutLightClient) GetTimestamp(clientId core.ClientId, height core.Height) core.Timestamp {
	return core.Timestamp(2)
}

func (m *timeoutLightClient) GetLatestHeight(clientId core.ClientId) core.Height {
	return core.Height(1)
}

func (m *timeoutLightClient) GetStatus(clientId core.ClientId) core.Status {
	return core.StatusActive
}

func main(cur realm) {
	pair := openTimeoutChannelPair(cross(cur))

	sender := testutils.TestAddress("g20-timeout-send")
	tok, ledger := newToken(cur, "Timeout Token", "TOT")
	grc20reg.Register(cross(cur), tok, "timeout_refund")
	denom := timeoutPkgPath + ".timeout_refund"
	ledger.Mint(sender, 15)
	ledger.Approve(sender, zkgm.ProxyAddress(), 9)

	order := z.TokenOrderV2{
		Sender:      []byte(sender.String()),
		BaseToken:   []byte(denom),
		BaseAmount:  u256.NewUint(9),
		QuoteToken:  []byte("remote/quote"),
		QuoteAmount: u256.NewUint(9),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}
	println("[INFO] before send local GRC20 is held by sender")
	println("sender_before_send", tok.BalanceOf(sender))
	println("proxy_before_send", tok.BalanceOf(zkgm.ProxyAddress()))
	println("channel_before_send", channelBalanceString(pair.Source, order.BaseToken, order.QuoteToken))

	stdtesting.SetRealm(stdtesting.NewUserRealm(sender))
	packet := zkgm.Send(cross(cur), pair.Source, core.Timestamp(1), [32]byte{}, e2e.MustTokenOrderInstruction(cross(cur), order))
	stdtesting.SetRealm(stdtesting.NewCodeRealm(timeoutPkgPath))

	println("")
	println("[SCENARIO] local GRC20 send escrows into proxy")
	println("sender_after_send", tok.BalanceOf(sender))
	println("proxy_after_send", tok.BalanceOf(zkgm.ProxyAddress()))
	println("channel_after_send", channelBalanceString(pair.Source, order.BaseToken, order.QuoteToken))
	println("commitment_after_send", core.HasPacketCommitment(cross(cur), packet))

	core.PacketTimeout(cross(cur), core.NewMsgPacketTimeout(cross(cur), packet, nil, core.Height(1)))

	println("")
	println("[SCENARIO] timeout refunds GRC20 escrow to sender")
	println("sender_after_timeout", tok.BalanceOf(sender))
	println("proxy_after_timeout", tok.BalanceOf(zkgm.ProxyAddress()))
	println("channel_after_timeout", channelBalanceString(pair.Source, order.BaseToken, order.QuoteToken))
	println("commitment_after_timeout", core.HasPacketCommitment(cross(cur), packet))
}

func openTimeoutChannelPair(cur realm) e2e.ChannelPair {
	if !core.HasClient(timeoutClientType) {
		core.RegisterClient(cross(cur), timeoutClientType, &timeoutLightClient{})
	}
	clientId := core.CreateClient(cross(cur), core.NewMsgCreateClient(cross(cur), timeoutClientType, nil, nil))
	connectionId := core.ConnectionOpenInit(cross(cur), core.NewMsgConnectionOpenInit(cross(cur), clientId, core.ClientId(99)))
	core.ConnectionOpenAck(cross(cur), core.NewMsgConnectionOpenAck(cross(cur), connectionId, core.ConnectionId(77), nil, core.Height(1)))

	portId := []byte(zkgm.ProxyPkgPath())
	source := core.ChannelOpenInit(cross(cur), core.NewMsgChannelOpenInit(cross(cur), portId, portId, connectionId, zkgm.Version))
	core.ChannelOpenAck(cross(cur), core.NewMsgChannelOpenAck(cross(cur), source, zkgm.Version, core.ChannelId(2), nil, core.Height(1)))
	return e2e.NewChannelPair(cross(cur), clientId, connectionId, source, core.ChannelId(2))
}

func newToken(cur realm, name string, symbol string) (*grc20.Token, *grc20.PrivateLedger) {
	return grc20.NewToken(0, cur, name, symbol, 0)
}

func channelBalanceString(channelId core.ChannelId, baseToken []byte, quoteToken []byte) string {
	balance := zkgm.GetChannelBalanceV2(impl.ChannelBalanceKeyV2(channelId, u256.Zero(), baseToken, quoteToken))
	if balance == nil {
		return "0"
	}
	return balance.ToString()
}

// Output:
// [INFO] before send local GRC20 is held by sender
// sender_before_send 15
// proxy_before_send 0
// channel_before_send 0
//
// [SCENARIO] local GRC20 send escrows into proxy
// sender_after_send 6
// proxy_after_send 9
// channel_after_send 9
// commitment_after_send true
//
// [SCENARIO] timeout refunds GRC20 escrow to sender
// sender_after_timeout 15
// proxy_after_timeout 0
// channel_after_timeout 0
// commitment_after_timeout false
