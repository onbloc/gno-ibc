// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/intent
package intent

// reject_forged_call_via_intent_filetest is the EXCEPTION-path intent scenario
// (re-targeted from the legacy e2e z27). The proofless market-maker fast path
// core.IntentPacketRecv dispatches OP_CALL to the receiver's OnIntentZkgm (not
// OnZkgm — a separate handler intent recv always calls, whether the receiver
// accepts or rejects it). A receiver that panics on OnIntentZkgm is caught by
// safeCallOnIntentZkgm and converted into ACK_ERR_ONLY_MAKER; OnIntentRecvPacket
// then panics with "only maker" rather than silently degrading, so a receiver
// that cannot vouch for the call without a real proof reverts the whole intent
// recv instead of committing a false success. The revert is the terminating
// panic, matched by the // Error: directive.

import (
	"chain"
	"testing"

	types "gno.land/p/onbloc/ibc/union/types"
	z "gno.land/p/onbloc/ibc/union/zkgm"

	u256 "gno.land/p/gnoswap/uint256"

	"gno.land/r/onbloc/ibc/union/access"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	_ "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	core "gno.land/r/onbloc/ibc/union/core"
	_ "gno.land/r/onbloc/ibc/union/core/v1"
	mocklc "gno.land/r/onbloc/ibc/testing/mock/lightclient"
	mockrcv "gno.land/r/onbloc/ibc/testing/mock/receiver"
)

const (
	coreImplPath  = "gno.land/r/onbloc/ibc/union/core/v1"
	zkgmImplPath  = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	mockLcPkgPath = "gno.land/r/onbloc/ibc/testing/mock/lightclient"
	receiverPath  = "gno.land/r/onbloc/ibc/testing/mock/receiver"

	adminAddr = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
)

func main(cur realm) {
	println("[SCENARIO] 1. Bootstrap, open a channel, and register a mock receiver that panics on intent calls")
	channelId := bootstrap(cur)
	println("")

	println("[SCENARIO] 2. A forged OP_CALL delivered via proofless intent recv is rejected: the receiver panic reverts the whole recv")
	forgedIntentCall(cur, channelId)
}

func bootstrap(cur realm) types.ChannelId {
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.UpdateImpl(cross(cur), coreImplPath)
	zkgm.UpdateImpl(cross(cur), zkgmImplPath)
	zkgm.SetRateLimitDisabled(cross(cur), true)
	zkgm.RegisterCoreApp(cross(cur))
	access.GrantRole(cross(cur), access.RelayerRole, adminAddr)
	access.GrantRole(cross(cur), access.RelayerRole, chain.PackageAddress(mockLcPkgPath))

	mocklc.RegisterMockLightClient(cross(cur))
	core.CreateClient(cross(cur), core.NewMsgCreateClient(mocklc.MockClientType, nil, nil))
	clientId := types.ClientId(1)

	core.ConnectionOpenInit(cross(cur), core.NewMsgConnectionOpenInit(clientId, types.ClientId(99)))
	connectionId := types.ConnectionId(1)
	core.ConnectionOpenAck(cross(cur), core.NewMsgConnectionOpenAck(connectionId, types.ConnectionId(77), nil, 1))

	portId := []byte(zkgm.ProxyPkgPath())
	core.ChannelOpenInit(cross(cur), core.NewMsgChannelOpenInit(portId, portId, connectionId, zkgm.Version, "g1relayer"))
	channelId := types.ChannelId(1)
	core.ChannelOpenAck(cross(cur), core.NewMsgChannelOpenAck(channelId, zkgm.Version, types.ChannelId(2), nil, 1, "g1relayer"))

	mockrcv.Reset(cross(cur))
	// Intent recv always calls OnIntentZkgm (never OnZkgm). Arm it to panic, as a
	// receiver would when it cannot vouch for a call without a real proof.
	mockrcv.SetPanic(cross(cur), "cannot accept unproven call")
	return channelId
}

// forgedIntentCall submits an OP_CALL through the proofless intent path. The
// receiver's OnIntentZkgm panics (armed in bootstrap); safeCallOnIntentZkgm
// catches it and converts it to ACK_ERR_ONLY_MAKER, and OnIntentRecvPacket
// panics on that sentinel rather than committing a success ack.
func forgedIntentCall(cur realm, channelId types.ChannelId) {
	call := z.Call{
		Sender:           []byte("attacker-sender"),
		ContractAddress:  []byte(receiverPath),
		ContractCalldata: []byte("forged-no-proof"),
	}
	packet := core.NewPacket(types.ChannelId(2), channelId, mustPacketData(mustCallInstruction(call)), types.Timestamp(1<<62))

	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.IntentPacketRecv(cross(cur), types.NewMsgIntentPacketRecv([]types.Packet{packet}, [][]byte{nil}))
}

// --- encoding helpers ---

func mustCallInstruction(call z.Call) z.Instruction {
	operand, err := z.EncodeCall(call)
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_0, Opcode: z.OP_CALL, Operand: operand}
}

func mustPacketData(instr z.Instruction) []byte {
	data, err := z.EncodeZkgmPacket(z.ZkgmPacket{Path: u256.Zero(), Instruction: instr})
	if err != nil {
		panic(err)
	}
	return data
}

// Output:
// [SCENARIO] 1. Bootstrap, open a channel, and register a mock receiver that panics on intent calls
//
// [SCENARIO] 2. A forged OP_CALL delivered via proofless intent recv is rejected: the receiver panic reverts the whole recv

// Error:
// only maker
