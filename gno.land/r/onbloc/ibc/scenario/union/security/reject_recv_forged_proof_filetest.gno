// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/security
package security

// reject_recv_forged_proof_filetest is the EXCEPTION-path security scenario (S-8.2).
// A receive is only accepted if the light client proves the packet's batch
// commitment is committed on the counterparty. This file backs the channel with a
// light client whose VerifyMembership always fails (a forged/invalid proof), so the
// receive is rejected before any receipt is written or any token minted — the
// terminating panic matched by // Error:.

import (
	"errors"
	"testing"

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
	receiverAddr  = address("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm")
	forgedLcType  = types.ClientType("scenario-forged-lc")
)

func main(cur realm) {
	println("[SCENARIO] 1. Bootstrap with a light client that rejects every membership proof")
	channelId := bootstrap(cur)
	println("")

	println("[SCENARIO] 2. A receive with a forged proof is rejected before any mint")
	attemptRecv(cur, channelId)
}

func bootstrap(cur realm) types.ChannelId {
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.UpdateImpl(cross(cur), coreImplPath)
	zkgm.UpdateImpl(cross(cur), zkgmImplPath)
	zkgm.SetRateLimitDisabled(cross(cur), true)
	zkgm.RegisterCoreApp(cross(cur))
	access.GrantRole(cross(cur), access.RelayerRole, adminAddr)

	core.RegisterClient(cross(cur), forgedLcType, func(_, _ []byte) (lightclient.Interface, error) {
		return &forgedLightClient{}, nil
	})
	core.CreateClient(cross(cur), core.NewMsgCreateClient(forgedLcType, nil, nil))
	clientId := types.ClientId(1)

	core.ConnectionOpenInit(cross(cur), core.NewMsgConnectionOpenInit(clientId, types.ClientId(99)))
	connectionId := types.ConnectionId(1)
	// Force-open so the handshake itself does not need the (failing) membership proof.
	core.ForceConnectionOpenAck(cross(cur), core.NewMsgConnectionOpenAck(connectionId, types.ConnectionId(77), nil, 0))

	portId := []byte(zkgm.ProxyPkgPath())
	core.ChannelOpenInit(cross(cur), core.NewMsgChannelOpenInit(portId, portId, connectionId, zkgm.Version, "g1relayer"))
	channelId := types.ChannelId(1)
	core.ForceChannelOpenAck(cross(cur), core.NewMsgChannelOpenAck(channelId, zkgm.Version, types.ChannelId(2), nil, 0, "g1relayer"))
	return channelId
}

func attemptRecv(cur realm, channelId types.ChannelId) {
	meta := mustTokenMetadata("grc20", z.TokenInitializer{Name: "Gno Token", Symbol: "GNOT", Decimals: 6})
	quoteToken := z.PredictWrappedTokenV2(u256.Zero(), uint32(channelId), []byte("ugnot"), z.MetadataImage(mustDecodeMeta(meta)))
	order := z.TokenOrderV2{
		Sender:      []byte("attacker"),
		Receiver:    []byte(receiverAddr.String()),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(100),
		QuoteToken:  []byte(quoteToken),
		QuoteAmount: u256.NewUint(100),
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
		Metadata:    meta,
	}
	packet := core.NewPacket(types.ChannelId(2), channelId, mustPacketData(mustOrderInstruction(order)), types.Timestamp(1<<62))

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

// --- forged light client: every membership proof fails ---

type forgedLightClient struct{}

func (m *forgedLightClient) VerifyMembership(uint64, []byte, []byte, []byte) error {
	return errors.New("forged proof: membership verification failed")
}
func (m *forgedLightClient) VerifyNonMembership(uint64, []byte, []byte) error     { return nil }
func (m *forgedLightClient) GetTimestamp() types.Timestamp                        { return types.Timestamp(1) }
func (m *forgedLightClient) GetTimestampAtHeight(uint64) (types.Timestamp, error) { return types.Timestamp(1), nil }
func (m *forgedLightClient) GetLatestHeight() uint64                              { return 1 }
func (m *forgedLightClient) GetCounterpartyChainID() string                       { return "forged-chain" }
func (m *forgedLightClient) Status() lightclient.Status                           { return lightclient.Active }

func (m *forgedLightClient) VerifyHeader(_ address, header []byte, _ address) (types.StateUpdate, error) {
	return types.StateUpdate{Height: 1, ClientStateBytes: header, ConsensusStateBytes: header}, nil
}

func (m *forgedLightClient) VerifyCreation(address, address) (types.ClientCreationResult, error) {
	return types.ClientCreationResult{}, nil
}

func (m *forgedLightClient) Misbehaviour(address, []byte, address) ([]byte, error) {
	return nil, errors.New("forged: misbehaviour unsupported")
}

// Output:
// [SCENARIO] 1. Bootstrap with a light client that rejects every membership proof
//
// [SCENARIO] 2. A receive with a forged proof is rejected before any mint

// Error:
// forged proof: membership verification failed
