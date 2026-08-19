// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/recovery
package recovery

// reject_recv_while_unpaused_under_recovery_impl_filetest: during the brief
// window recovery needs SendRaw unpaused, ordinary relayer traffic is still
// fail-closed — v2_locked_recovery panics on OnRecvPacket, so the proxy pause
// gate isn't the only thing standing between an attacker and normal service.

import (
	"encoding/hex"
	"testing"

	"gno.land/p/onbloc/ibc/union/lightclient"
	types "gno.land/p/onbloc/ibc/union/types"
	z "gno.land/p/onbloc/ibc/union/zkgm"

	u256 "gno.land/p/onbloc/math/uint256"

	"gno.land/r/onbloc/ibc/union/access"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	_ "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	_ "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v2_locked_recovery"
	core "gno.land/r/onbloc/ibc/union/core"
	_ "gno.land/r/onbloc/ibc/union/core/v1"
)

const (
	unpausedCoreImplPath         = "gno.land/r/onbloc/ibc/union/core/v1"
	unpausedZkgmImplPath         = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	unpausedZkgmRecoveryImplPath = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v2_locked_recovery"

	unpausedAdminAddr      = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
	unpausedReceiverAddr   = address("g1dyxy88p94acjnm8dmu9tfj2mv2ncvx83cagllu")
	unpausedMockClientType = types.ClientType("scenario-mock-lc-unpaused")
)

func main(cur realm) {
	println("[SCENARIO] 1. Bootstrap IBC host and open a zkgm channel (impl = v1)")
	channelId := unpausedBootstrap(cur)
	println("")

	println("[SCENARIO] 2. Admin installs the recovery-only impl via UpdateImpl, without pausing")
	testing.SetRealm(testing.NewUserRealm(unpausedAdminAddr))
	zkgm.UpdateImpl(cross(cur), unpausedZkgmRecoveryImplPath)
	println("[INFO] impl switched to v2_locked_recovery, app left unpaused (the recovery-window state)")
	println("")

	println("[SCENARIO] 3. A receive during the unpaused recovery window is still rejected by the impl")
	unpausedAttemptReceive(cur, channelId)
}

// unpausedBootstrap opens the channel under v1 first: v2_locked_recovery panics on channel-handshake callbacks.
func unpausedBootstrap(cur realm) types.ChannelId {
	testing.SetRealm(testing.NewUserRealm(unpausedAdminAddr))
	core.UpdateImpl(cross(cur), unpausedCoreImplPath)
	zkgm.UpdateImpl(cross(cur), unpausedZkgmImplPath)
	zkgm.SetRateLimitDisabled(cross(cur), true)
	zkgm.RegisterCoreApp(cross(cur))
	access.GrantRole(cross(cur), access.RelayerRole, unpausedAdminAddr)

	core.RegisterClient(cross(cur), unpausedMockClientType, func(_, _ []byte) (lightclient.Interface, error) {
		return &unpausedMockLightClient{}, nil
	})
	core.CreateClient(cross(cur), core.NewMsgCreateClient(unpausedMockClientType, nil, nil))
	clientId := types.ClientId(1)

	core.ConnectionOpenInit(cross(cur), core.NewMsgConnectionOpenInit(clientId, types.ClientId(99)))
	connectionId := types.ConnectionId(1)
	core.ConnectionOpenAck(cross(cur), core.NewMsgConnectionOpenAck(connectionId, types.ConnectionId(77), nil, 1))

	portId := []byte(zkgm.ProxyPkgPath())
	core.ChannelOpenInit(cross(cur), core.NewMsgChannelOpenInit(portId, portId, connectionId, zkgm.Version, "g1relayer"))
	channelId := types.ChannelId(1)
	core.ChannelOpenAck(cross(cur), core.NewMsgChannelOpenAck(channelId, zkgm.Version, types.ChannelId(2), nil, 1, "g1relayer"))
	return channelId
}

// unpausedAttemptReceive submits an ordinary INITIALIZE order while unpaused; expect the impl to reject it.
func unpausedAttemptReceive(cur realm, channelId types.ChannelId) {
	meta := unpausedMustTokenMetadata("af739f34ddf951cbc24fdbba4f76213688e13627", z.TokenInitializer{Name: "Gno Token", Symbol: "GNOT", Decimals: 6})
	quoteToken := z.PredictWrappedTokenV2(u256.Zero(), uint32(channelId), []byte("ugnot"), z.MetadataImage(unpausedMustDecodeMeta(meta)))
	order := z.TokenOrderV2{
		Sender:      []byte("remote-sender"),
		Receiver:    []byte(unpausedReceiverAddr.String()),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(100),
		QuoteToken:  []byte(quoteToken),
		QuoteAmount: u256.NewUint(100),
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
		Metadata:    meta,
	}
	packet := core.NewPacket(types.ChannelId(2), channelId, unpausedMustPacketData(unpausedMustOrderInstruction(order)), types.Timestamp(1<<62))

	testing.SetRealm(testing.NewUserRealm(unpausedAdminAddr))
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{packet}, [][]byte{nil}, nil, 1))
}

// --- encoding helpers ---

func unpausedMustOrderInstruction(order z.TokenOrderV2) z.Instruction {
	operand, err := z.EncodeTokenOrderV2(order)
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_2, Opcode: z.OP_TOKEN_ORDER, Operand: operand}
}

func unpausedMustPacketData(instr z.Instruction) []byte {
	data, err := z.EncodeZkgmPacket(z.ZkgmPacket{Path: u256.Zero(), Instruction: instr})
	if err != nil {
		panic(err)
	}
	return data
}

func unpausedMustTokenMetadata(implementationHex string, ti z.TokenInitializer) []byte {
	implementation, err := hex.DecodeString(implementationHex)
	if err != nil {
		panic(err)
	}
	initBytes, err := z.EncodeTokenInitializer(ti)
	if err != nil {
		panic(err)
	}
	meta, err := z.EncodeTokenMetadata(z.TokenMetadata{Implementation: implementation, Initializer: initBytes})
	if err != nil {
		panic(err)
	}
	return meta
}

func unpausedMustDecodeMeta(bz []byte) z.TokenMetadata {
	meta, err := z.DecodeTokenMetadata(bz)
	if err != nil {
		panic(err)
	}
	return meta
}

// --- permissive mock light client (accepts any proof) ---

type unpausedMockLightClient struct{}

func (m *unpausedMockLightClient) VerifyMembership(uint64, []byte, []byte, []byte) error { return nil }
func (m *unpausedMockLightClient) VerifyNonMembership(uint64, []byte, []byte) error      { return nil }
func (m *unpausedMockLightClient) GetTimestamp() types.Timestamp                         { return types.Timestamp(1) }

func (m *unpausedMockLightClient) GetTimestampAtHeight(uint64) (types.Timestamp, error) {
	return types.Timestamp(1), nil
}
func (m *unpausedMockLightClient) GetLatestHeight() uint64        { return 1 }
func (m *unpausedMockLightClient) GetCounterpartyChainID() string { return "mock-chain" }

func (m *unpausedMockLightClient) Status() lightclient.Status { return lightclient.Active }

func (m *unpausedMockLightClient) VerifyHeader(_ address, header []byte, _ address) (types.StateUpdate, error) {
	return types.StateUpdate{Height: 1, ClientStateBytes: header, ConsensusStateBytes: header}, nil
}

func (m *unpausedMockLightClient) VerifyCreation(address, address) (types.ClientCreationResult, error) {
	return types.ClientCreationResult{}, nil
}

func (m *unpausedMockLightClient) Misbehaviour(address, []byte, address) ([]byte, error) {
	return nil, unpausedMockError("mock: misbehaviour unsupported")
}

type unpausedMockError string

func (e unpausedMockError) Error() string { return string(e) }

// Output:
// [SCENARIO] 1. Bootstrap IBC host and open a zkgm channel (impl = v1)
//
// [SCENARIO] 2. Admin installs the recovery-only impl via UpdateImpl, without pausing
// [INFO] impl switched to v2_locked_recovery, app left unpaused (the recovery-window state)
//
// [SCENARIO] 3. A receive during the unpaused recovery window is still rejected by the impl

// Error:
// recovery impl: OnRecvPacket not supported
