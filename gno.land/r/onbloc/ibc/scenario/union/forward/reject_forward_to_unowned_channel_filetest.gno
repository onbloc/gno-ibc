// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/forward
package forward

// A forward's next-hop channel is owned by a different port than zkgm's.
// core.SendPacket would panic on this (ErrUnauthorizedPacketSender), which
// can't be recovered across the cross(rlm) boundary on-chain, so
// verifyForwardChannel now rejects it first. Confirmed by: recv completes
// without panicking, and the child is never committed on the unowned channel.

import (
	"chain"
	"testing"

	"gno.land/p/nt/ufmt/v0"
	types "gno.land/p/onbloc/ibc/union/types"
	z "gno.land/p/onbloc/ibc/union/zkgm"

	u256 "gno.land/p/onbloc/math/uint256"

	mocklc "gno.land/r/onbloc/ibc/testing/mock/lightclient"
	"gno.land/r/onbloc/ibc/union/access"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	_ "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	core "gno.land/r/onbloc/ibc/union/core"
	_ "gno.land/r/onbloc/ibc/union/core/v1"
)

const (
	coreImplPathUnowned  = "gno.land/r/onbloc/ibc/union/core/v1"
	zkgmImplPathUnowned  = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	mockLcPkgPathUnowned = "gno.land/r/onbloc/ibc/testing/mock/lightclient"

	adminAddrUnowned = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")

	// otherPort is a distinct app registered at a different realm than zkgm.
	// Channel 2 is opened at this port, so the forward's next-hop channel
	// exists but is not owned by the zkgm proxy.
	otherPort = "gno.land/r/onbloc/ibc/scenario/union/forward"

	parentChannelUnowned = uint32(1) // local parent channel; counterparty 101
	otherChannelUnowned  = uint32(2) // local channel owned by otherPort; counterparty 102
)

func main(cur realm) {
	println("[SCENARIO] 1. Bootstrap: open the parent channel (1) for zkgm and channel 2 for a DIFFERENT port")
	bootstrapUnowned(cur)
	println("")

	println("[SCENARIO] 2. Receive an OP_FORWARD naming channel 2 (not zkgm's) as the next hop")
	recvForwardToUnownedChannel(cur)
}

func bootstrapUnowned(cur realm) {
	testing.SetRealm(testing.NewUserRealm(adminAddrUnowned))
	core.UpdateImpl(cross(cur), coreImplPathUnowned)
	zkgm.UpdateImpl(cross(cur), zkgmImplPathUnowned)
	zkgm.SetRateLimitDisabled(cross(cur), true)
	zkgm.RegisterCoreApp(cross(cur))
	access.GrantRole(cross(cur), access.RelayerRole, adminAddrUnowned)
	access.GrantRole(cross(cur), access.RelayerRole, chain.PackageAddress(mockLcPkgPathUnowned))

	mocklc.RegisterMockLightClient(cross(cur))
	core.CreateClient(cross(cur), core.NewMsgCreateClient(mocklc.MockClientType, nil, nil))
	clientId := types.ClientId(1)

	core.ConnectionOpenInit(cross(cur), core.NewMsgConnectionOpenInit(clientId, types.ClientId(99)))
	connectionId := types.ConnectionId(1)
	core.ConnectionOpenAck(cross(cur), core.NewMsgConnectionOpenAck(connectionId, types.ConnectionId(77), nil, 1))

	// Channel 1: zkgm's own port. This is the parent packet's destination.
	zkgmPortId := []byte(zkgm.ProxyPkgPath())
	core.ChannelOpenInit(cross(cur), core.NewMsgChannelOpenInit(zkgmPortId, zkgmPortId, connectionId, zkgm.Version, "g1relayer"))
	core.ChannelOpenAck(cross(cur), core.NewMsgChannelOpenAck(types.ChannelId(1), zkgm.Version, types.ChannelId(101), nil, 1, "g1relayer"))

	// Channel 2: a DIFFERENT port's app, registered from this scenario realm.
	testing.SetRealm(testing.NewCodeRealm(otherPort))
	core.RegisterApp(cross(cur), &otherApp{})
	testing.SetRealm(testing.NewUserRealm(adminAddrUnowned))
	otherPortId := []byte(otherPort)
	core.ChannelOpenInit(cross(cur), core.NewMsgChannelOpenInit(otherPortId, otherPortId, connectionId, "other-v1", "g1relayer"))
	core.ChannelOpenAck(cross(cur), core.NewMsgChannelOpenAck(types.ChannelId(2), "other-v1", types.ChannelId(102), nil, 1, "g1relayer"))
}

func recvForwardToUnownedChannel(cur realm) {
	var salt [32]byte
	salt[31] = 9
	call := z.Call{Sender: []byte("forwarder"), ContractAddress: []byte("gno.land/r/onbloc/ibc/testing/mock/receiver"), ContractCalldata: []byte("forwarded-call")}
	forward := z.Forward{
		Path:             forwardPathUnowned(parentChannelUnowned, otherChannelUnowned),
		TimeoutHeight:    0,
		TimeoutTimestamp: uint64(1) << 62,
		Instruction:      mustCallInstructionUnowned(call),
	}
	parent := core.NewPacket(types.ChannelId(101), types.ChannelId(parentChannelUnowned), saltedForwardDataUnowned(salt, forward), types.Timestamp(1<<62))

	child := deriveChildUnowned(salt, forward)

	testing.SetRealm(testing.NewUserRealm(adminAddrUnowned))
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{parent}, [][]byte{nil}, nil, 1))

	ufmt.Printf("[INFO] parent packet receipt recorded (recv did not panic): %t\n", receiptRecordedUnowned(parent))
	ufmt.Printf("[INFO] child packet committed on the unowned channel: %t\n", committedUnowned(child))
	ufmt.Println("[EXPECTED] recv completes with a failure result instead of panicking; no child is ever sent to the unowned channel")
}

// deriveChildUnowned reconstructs the single-hop child packet exactly as
// buildForwardChild would, so we can assert it was never committed.
func deriveChildUnowned(parentSalt [32]byte, forward z.Forward) types.Packet {
	childData := mustZkgmPacketDataUnowned(z.ZkgmPacket{
		Salt:        z.DeriveForwardSalt(parentSalt),
		Path:        forwardPathUnowned(parentChannelUnowned, otherChannelUnowned),
		Instruction: forward.Instruction,
	})
	return core.NewPacket(types.ChannelId(otherChannelUnowned), types.ChannelId(102), childData, types.Timestamp(forward.TimeoutTimestamp))
}

func forwardPathUnowned(prevDest, nextSource uint32) *u256.Uint {
	p, err := z.UpdateChannelPath(u256.Zero(), prevDest)
	if err != nil {
		panic(err)
	}
	p, err = z.UpdateChannelPath(p, nextSource)
	if err != nil {
		panic(err)
	}
	return p
}

func committedUnowned(packet types.Packet) bool {
	_, err := core.GetBatchPackets(core.CommitPacketsHash([]types.Packet{packet}))
	return err == nil
}

func receiptRecordedUnowned(packet types.Packet) bool {
	_, err := core.GetBatchReceipts(core.CommitPacketsHash([]types.Packet{packet}))
	return err == nil
}

func mustCallInstructionUnowned(call z.Call) z.Instruction {
	operand, err := z.EncodeCall(call)
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_0, Opcode: z.OP_CALL, Operand: operand}
}

func saltedForwardDataUnowned(salt [32]byte, forward z.Forward) []byte {
	operand, err := z.EncodeForward(forward)
	if err != nil {
		panic(err)
	}
	return mustZkgmPacketDataUnowned(z.ZkgmPacket{Salt: salt, Path: u256.Zero(), Instruction: z.Instruction{Version: z.INSTR_VERSION_0, Opcode: z.OP_FORWARD, Operand: operand}})
}

func mustZkgmPacketDataUnowned(zp z.ZkgmPacket) []byte {
	data, err := z.EncodeZkgmPacket(zp)
	if err != nil {
		panic(err)
	}
	return data
}

// otherApp is a minimal IApp implementer registered at otherPort so channel 2
// exists but is owned by a realm other than zkgm.
type otherApp struct{}

func (a *otherApp) OnChannelOpenInit(_ realm, _ types.ConnectionId, _ types.ChannelId, _ string, _ address) {
}

func (a *otherApp) OnChannelOpenTry(_ realm, _ types.ConnectionId, _ types.ChannelId, _ string, _ string, _ address) {
}

func (a *otherApp) OnChannelOpenAck(_ realm, _ types.ChannelId, _ types.ChannelId, _ string, _ address) {
}

func (a *otherApp) OnChannelOpenConfirm(_ realm, _ types.ChannelId, _ address) {}
func (a *otherApp) OnChannelCloseInit(_ realm, _ types.ChannelId, _ address)    {}
func (a *otherApp) OnChannelCloseConfirm(_ realm, _ types.ChannelId, _ address) {}

func (a *otherApp) OnRecvPacket(_ realm, _ types.Packet, _ address, _ []byte) types.RecvPacketResult {
	return core.NewRecvPacketResult(types.PacketStatusSuccess, nil)
}

func (a *otherApp) OnAcknowledgementPacket(_ realm, _ types.Packet, _ []byte, _ address) {}
func (a *otherApp) OnTimeoutPacket(_ realm, _ types.Packet, _ address)                   {}

func (a *otherApp) OnIntentRecvPacket(_ realm, _ types.Packet, _ address, _ []byte) types.RecvPacketResult {
	return core.NewRecvPacketResult(types.PacketStatusSuccess, nil)
}

// Output:
// [SCENARIO] 1. Bootstrap: open the parent channel (1) for zkgm and channel 2 for a DIFFERENT port
//
// [SCENARIO] 2. Receive an OP_FORWARD naming channel 2 (not zkgm's) as the next hop
// [INFO] parent packet receipt recorded (recv did not panic): true
// [INFO] child packet committed on the unowned channel: false
// [EXPECTED] recv completes with a failure result instead of panicking; no child is ever sent to the unowned channel
