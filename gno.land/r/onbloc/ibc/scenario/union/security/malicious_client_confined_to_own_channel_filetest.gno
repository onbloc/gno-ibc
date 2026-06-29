// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/security
package security

// malicious_client_confined_to_own_channel_filetest is the EXCEPTION-path security
// scenario for client-trust isolation (S-8.3 / D1). A channel's authenticity rests on
// the light client behind its connection. An attacker can register an always-accepting
// client and open their OWN channel on it — but that only lets them mint within their
// own channel's namespace; it gives them no power over a channel backed by an honest
// client. This file sets up two channels: a malicious one (always-verify client) and a
// legitimate one (honest client that rejects unproven membership). A forged receive on
// the malicious channel succeeds and mints an attacker-namespaced voucher (their
// sandbox), but the same forged receive on the legitimate channel is rejected by the
// honest client — the malicious client cannot reach across to forge there. The
// terminating panic on the legitimate channel is the assertion.

import (
	"errors"
	"testing"

	"gno.land/p/nt/ufmt/v0"
	"gno.land/p/onbloc/ibc/union/lightclient"
	types "gno.land/p/onbloc/ibc/union/types"
	z "gno.land/p/onbloc/ibc/union/zkgm"

	u256 "gno.land/p/gnoswap/uint256"

	"gno.land/r/onbloc/ibc/union/access"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	_ "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	core "gno.land/r/onbloc/ibc/union/core"
	_ "gno.land/r/onbloc/ibc/union/core/v1"
)

const (
	coreImplPath = "gno.land/r/onbloc/ibc/union/core/v1"
	zkgmImplPath = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"

	adminAddr     = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
	attackerAddr  = address("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm")
	maliciousType = types.ClientType("scenario-malicious-lc")
	legitType     = types.ClientType("scenario-legit-lc")

	maliciousChannel = uint32(1) // backed by the attacker's always-verify client
	legitChannel     = uint32(2) // backed by an honest client
)

func main(cur realm) {
	println("[SCENARIO] 1. Bootstrap: a malicious always-verify channel and a legit honest channel")
	bootstrap(cur)
	println("")

	meta := mustTokenMetadata("grc20", z.TokenInitializer{Name: "Gno Token", Symbol: "GNOT", Decimals: 6})

	println("[SCENARIO] 2. Forged recv on the MALICIOUS channel succeeds (attacker's own sandbox)")
	maliciousQuote := z.PredictWrappedTokenV2(u256.Zero(), maliciousChannel, []byte("ugnot"), z.MetadataImage(mustDecodeMeta(meta)))
	recvForged(cur, maliciousChannel, types.ChannelId(101), maliciousQuote, meta)
	ufmt.Printf("[INFO] attacker voucher on the malicious channel: %d\n", zkgm.VoucherBalanceOf(maliciousQuote, attackerAddr))
	ufmt.Println("[EXPECTED] 100 minted: the attacker dominates only their own channel's namespace")
	println("")

	println("[SCENARIO] 3. The same forged recv on the LEGIT channel is rejected by the honest client")
	legitQuote := z.PredictWrappedTokenV2(u256.Zero(), legitChannel, []byte("ugnot"), z.MetadataImage(mustDecodeMeta(meta)))
	recvForged(cur, legitChannel, types.ChannelId(102), legitQuote, meta)
}

func bootstrap(cur realm) {
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.UpdateImpl(cross(cur), coreImplPath)
	zkgm.UpdateImpl(cross(cur), zkgmImplPath)
	zkgm.SetRateLimitDisabled(cross(cur), true)
	zkgm.RegisterCoreApp(cross(cur))
	access.GrantRole(cross(cur), access.RelayerRole, adminAddr)

	// Client 1 + channel 1: the attacker's always-verify (malicious) client.
	core.RegisterClient(cross(cur), maliciousType, func(_, _ []byte) (lightclient.Interface, error) {
		return &acceptingClient{}, nil
	})
	core.CreateClient(cross(cur), core.NewMsgCreateClient(maliciousType, nil, nil))
	openChannel(cur, types.ClientId(1), types.ConnectionId(1), types.ChannelId(maliciousChannel), types.ChannelId(101))

	// Client 2 + channel 2: an honest client that rejects unproven membership.
	core.RegisterClient(cross(cur), legitType, func(_, _ []byte) (lightclient.Interface, error) {
		return &honestClient{}, nil
	})
	core.CreateClient(cross(cur), core.NewMsgCreateClient(legitType, nil, nil))
	openChannel(cur, types.ClientId(2), types.ConnectionId(2), types.ChannelId(legitChannel), types.ChannelId(102))
}

// openChannel force-opens a connection and channel so the handshake itself does not need
// a membership proof (the honest client would reject one); the RECV verification is what
// the scenario exercises.
func openChannel(cur realm, clientId types.ClientId, connectionId types.ConnectionId, channelId, counterparty types.ChannelId) {
	core.ConnectionOpenInit(cross(cur), core.NewMsgConnectionOpenInit(clientId, types.ClientId(99)))
	core.ForceConnectionOpenAck(cross(cur), core.NewMsgConnectionOpenAck(connectionId, types.ConnectionId(77), nil, 0))

	portId := []byte(zkgm.ProxyPkgPath())
	core.ChannelOpenInit(cross(cur), core.NewMsgChannelOpenInit(portId, portId, connectionId, zkgm.Version, "g1relayer"))
	core.ForceChannelOpenAck(cross(cur), core.NewMsgChannelOpenAck(channelId, zkgm.Version, counterparty, nil, 0, "g1relayer"))
}

func recvForged(cur realm, destChannel uint32, sourceChannel types.ChannelId, quoteToken string, meta []byte) {
	order := z.TokenOrderV2{
		Sender:      []byte("attacker"),
		Receiver:    []byte(attackerAddr.String()),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(100),
		QuoteToken:  []byte(quoteToken),
		QuoteAmount: u256.NewUint(100),
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
		Metadata:    meta,
	}
	packet := core.NewPacket(sourceChannel, types.ChannelId(destChannel), mustPacketData(mustOrderInstruction(order)), types.Timestamp(1<<62))

	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{packet}, [][]byte{[]byte("forged-proof")}, nil, 1))
}

// --- encoding helpers ---

func mustOrderInstruction(order z.TokenOrderV2) z.Instruction {
	operand, err := z.EncodeTokenOrderV2(order)
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_2, Opcode: z.OP_TOKEN_ORDER, Operand: operand}
}

func mustPacketData(instr z.Instruction) []byte {
	data, err := z.EncodeZkgmPacket(z.ZkgmPacket{Path: u256.Zero(), Instruction: instr})
	if err != nil {
		panic(err)
	}
	return data
}

func mustTokenMetadata(implementation string, ti z.TokenInitializer) []byte {
	initBytes, err := z.EncodeTokenInitializer(ti)
	if err != nil {
		panic(err)
	}
	meta, err := z.EncodeTokenMetadata(z.TokenMetadata{Implementation: []byte(implementation), Initializer: initBytes})
	if err != nil {
		panic(err)
	}
	return meta
}

func mustDecodeMeta(bz []byte) z.TokenMetadata {
	meta, err := z.DecodeTokenMetadata(bz)
	if err != nil {
		panic(err)
	}
	return meta
}

// --- always-verify (malicious) light client: accepts every membership proof ---

type acceptingClient struct{}

func (m *acceptingClient) VerifyMembership(uint64, []byte, []byte, []byte) error    { return nil }
func (m *acceptingClient) VerifyNonMembership(uint64, []byte, []byte) error         { return nil }
func (m *acceptingClient) GetTimestamp() types.Timestamp                            { return types.Timestamp(1) }
func (m *acceptingClient) GetTimestampAtHeight(uint64) (types.Timestamp, error)     { return types.Timestamp(1), nil }
func (m *acceptingClient) GetLatestHeight() uint64                                  { return 1 }
func (m *acceptingClient) GetCounterpartyChainID() string                           { return "malicious-chain" }
func (m *acceptingClient) Status() lightclient.Status                               { return lightclient.Active }
func (m *acceptingClient) VerifyHeader(_ address, h []byte, _ address) (types.StateUpdate, error) {
	return types.StateUpdate{Height: 1, ClientStateBytes: h, ConsensusStateBytes: h}, nil
}
func (m *acceptingClient) VerifyCreation(address, address) (types.ClientCreationResult, error) {
	return types.ClientCreationResult{}, nil
}
func (m *acceptingClient) Misbehaviour(address, []byte, address) ([]byte, error) { return nil, nil }

// --- honest light client: rejects every (forged) membership proof ---

type honestClient struct{}

func (m *honestClient) VerifyMembership(uint64, []byte, []byte, []byte) error {
	return errors.New("honest client: membership verification failed")
}
func (m *honestClient) VerifyNonMembership(uint64, []byte, []byte) error        { return nil }
func (m *honestClient) GetTimestamp() types.Timestamp                           { return types.Timestamp(1) }
func (m *honestClient) GetTimestampAtHeight(uint64) (types.Timestamp, error)    { return types.Timestamp(1), nil }
func (m *honestClient) GetLatestHeight() uint64                                 { return 1 }
func (m *honestClient) GetCounterpartyChainID() string                          { return "honest-chain" }
func (m *honestClient) Status() lightclient.Status                              { return lightclient.Active }
func (m *honestClient) VerifyHeader(_ address, h []byte, _ address) (types.StateUpdate, error) {
	return types.StateUpdate{Height: 1, ClientStateBytes: h, ConsensusStateBytes: h}, nil
}
func (m *honestClient) VerifyCreation(address, address) (types.ClientCreationResult, error) {
	return types.ClientCreationResult{}, nil
}
func (m *honestClient) Misbehaviour(address, []byte, address) ([]byte, error) {
	return nil, errors.New("honest: misbehaviour unsupported")
}

// Output:
// [SCENARIO] 1. Bootstrap: a malicious always-verify channel and a legit honest channel
//
// [SCENARIO] 2. Forged recv on the MALICIOUS channel succeeds (attacker's own sandbox)
// [INFO] attacker voucher on the malicious channel: 100
// [EXPECTED] 100 minted: the attacker dominates only their own channel's namespace
//
// [SCENARIO] 3. The same forged recv on the LEGIT channel is rejected by the honest client

// Error:
// honest client: membership verification failed
