// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/forward
package forward

// reject_nested_forward_child_filetest is the BOUNDARY forward scenario. A
// forward child may only be OP_CALL, OP_TOKEN_ORDER, or OP_BATCH — a directly nested
// OP_FORWARD child is rejected (multi-hop is expressed through the channel path, not by
// nesting forward instructions). On receive, executeForward is the only line of defense
// (recv skips verifyInternal), so it checks the child opcode against the allowlist and,
// on a miss, returns an error that becomes a synchronous universal-error
// acknowledgement rather than parking the parent in-flight. This file contrasts the two
// outcomes in one transcript: valid forward children (OP_CALL, OP_TOKEN_ORDER, and
// OP_BATCH) leave the parent receipt "committed" (async, ack deferred until the child
// resolves), while a nested-forward child leaves the parent receipt "ack-written"
// immediately and no child commitment.

import (
	"chain"
	"testing"

	"gno.land/p/nt/ufmt/v0"
	types "gno.land/p/onbloc/ibc/union/types"
	z "gno.land/p/onbloc/ibc/union/zkgm"

	u256 "gno.land/p/gnoswap/uint256"

	"gno.land/r/onbloc/ibc/union/access"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	_ "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	core "gno.land/r/onbloc/ibc/union/core"
	_ "gno.land/r/onbloc/ibc/union/core/v1"
	mocklc "gno.land/r/onbloc/ibc/testing/mock/lightclient"
)

const (
	coreImplPath  = "gno.land/r/onbloc/ibc/union/core/v1"
	zkgmImplPath  = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	mockLcPkgPath = "gno.land/r/onbloc/ibc/testing/mock/lightclient"
	receiverPath  = "gno.land/r/onbloc/ibc/testing/mock/receiver"

	adminAddr = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")

	parentChannel = uint32(1) // local parent channel; counterparty 101
	childChannel  = uint32(2) // local child source channel; counterparty 102
)

func main(cur realm) {
	println("[SCENARIO] 1. Bootstrap and open the parent (1) and child source (2) channels")
	bootstrap(cur)
	println("")

	println("[SCENARIO] 2. A forward with an allowed OP_CALL child is accepted (parked async)")
	validParent, validChild := recvForwardWith(cur, saltSeed(1), mustCallInstruction())
	ufmt.Printf("[INFO] valid forward  -> parent receipt: %s, child commitment: %s\n", receiptState(validParent), sendState(validChild))
	ufmt.Println("[EXPECTED] committed: parent parked in-flight, child relayed, ack deferred until the child resolves")
	println("")

	println("[SCENARIO] 3. A forward with an allowed OP_TOKEN_ORDER child is accepted (parked async)")
	tokenParent, tokenChild := recvForwardWith(cur, saltSeed(2), mustTokenOrderInstruction())
	ufmt.Printf("[INFO] token child    -> parent receipt: %s, child commitment: %s\n", receiptState(tokenParent), sendState(tokenChild))
	ufmt.Println("[EXPECTED] committed: TokenOrder child is relayed as the forward child packet")
	println("")

	println("[SCENARIO] 4. A forward with an allowed OP_BATCH child is accepted (parked async)")
	batchParent, batchChild := recvForwardWith(cur, saltSeed(3), mustBatchInstruction())
	ufmt.Printf("[INFO] batch child    -> parent receipt: %s, child commitment: %s\n", receiptState(batchParent), sendState(batchChild))
	ufmt.Println("[EXPECTED] committed: Batch child is relayed as the forward child packet")
	println("")

	println("[SCENARIO] 5. A forward with a nested OP_FORWARD child is rejected (synchronous failure ack)")
	nestedParent, nestedChild := recvForwardWith(cur, saltSeed(4), nestedForwardInstruction())
	ufmt.Printf("[INFO] nested forward -> parent receipt: %s, would-be child commitment: %s\n", receiptState(nestedParent), sendState(nestedChild))
	ufmt.Println("[EXPECTED] ack-written: rejected by the child allowlist, would-be child absent, parent not in-flight")
}

func bootstrap(cur realm) {
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
	core.ChannelOpenAck(cross(cur), core.NewMsgChannelOpenAck(types.ChannelId(1), zkgm.Version, types.ChannelId(101), nil, 1, "g1relayer"))
	core.ChannelOpenInit(cross(cur), core.NewMsgChannelOpenInit(portId, portId, connectionId, zkgm.Version, "g1relayer"))
	core.ChannelOpenAck(cross(cur), core.NewMsgChannelOpenAck(types.ChannelId(2), zkgm.Version, types.ChannelId(102), nil, 1, "g1relayer"))
}

// recvForwardWith receives a forward carrying the given inner instruction and returns
// the parent and would-be child packets so their commitments can be inspected.
func recvForwardWith(cur realm, salt [32]byte, inner z.Instruction) (types.Packet, types.Packet) {
	forward := z.Forward{
		Path:             forwardPath(parentChannel, childChannel),
		TimeoutHeight:    0,
		TimeoutTimestamp: uint64(1) << 62,
		Instruction:      inner,
	}
	parent := core.NewPacket(types.ChannelId(101), types.ChannelId(parentChannel), saltedForwardData(salt, forward), types.Timestamp(1<<62))
	child := deriveChild(salt, forward)

	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{parent}, [][]byte{nil}, nil, 1))
	return parent, child
}

// deriveChild reconstructs the single-hop child packet exactly as buildForwardChild
// does, so its commitment key can be looked up.
func deriveChild(parentSalt [32]byte, forward z.Forward) types.Packet {
	childData := mustZkgmPacketData(z.ZkgmPacket{
		Salt:        z.DeriveForwardSalt(parentSalt),
		Path:        forwardPath(parentChannel, childChannel),
		Instruction: forward.Instruction,
	})
	return core.NewPacket(types.ChannelId(childChannel), types.ChannelId(102), childData, types.Timestamp(forward.TimeoutTimestamp))
}

func receiptState(packet types.Packet) string {
	v, err := core.GetBatchReceipts(core.CommitPacketsHash([]types.Packet{packet}))
	return commitmentState(v, err)
}

func sendState(packet types.Packet) string {
	v, err := core.GetBatchPackets(core.CommitPacketsHash([]types.Packet{packet}))
	return commitmentState(v, err)
}

func commitmentState(v types.H256, err error) string {
	if err != nil {
		return "none"
	}
	switch v {
	case types.COMMITMENT_MAGIC:
		return "committed"
	case types.COMMITMENT_MAGIC_ACK:
		return "acknowledged"
	default:
		return "ack-written"
	}
}

// --- instruction builders ---

func mustCallInstruction() z.Instruction {
	call := z.Call{Sender: []byte("forwarder"), ContractAddress: []byte(receiverPath), ContractCalldata: []byte("forwarded-call")}
	operand, err := z.EncodeCall(call)
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_0, Opcode: z.OP_CALL, Operand: operand}
}

func mustTokenOrderInstruction() z.Instruction {
	order := z.TokenOrderV2{
		Sender:      []byte("forwarder"),
		Receiver:    []byte(adminAddr.String()),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(1),
		QuoteToken:  []byte("quote-token"),
		QuoteAmount: u256.NewUint(1),
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
	}
	operand, err := z.EncodeTokenOrderV2(order)
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_2, Opcode: z.OP_TOKEN_ORDER, Operand: operand}
}

func mustBatchInstruction() z.Instruction {
	operand, err := z.EncodeBatch(z.Batch{Instructions: []z.Instruction{mustCallInstruction()}})
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_0, Opcode: z.OP_BATCH, Operand: operand}
}

// nestedForwardInstruction is an inner instruction whose opcode is OP_FORWARD, which the
// child allowlist rejects before the operand is ever decoded.
func nestedForwardInstruction() z.Instruction {
	return z.Instruction{Version: z.INSTR_VERSION_0, Opcode: z.OP_FORWARD, Operand: []byte("nested-forward-operand")}
}

func saltSeed(b byte) [32]byte {
	var s [32]byte
	s[31] = b
	return s
}

func forwardPath(prevDest, nextSource uint32) *u256.Uint {
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

func saltedForwardData(salt [32]byte, forward z.Forward) []byte {
	operand, err := z.EncodeForward(forward)
	if err != nil {
		panic(err)
	}
	data, err := z.EncodeZkgmPacket(z.ZkgmPacket{Salt: salt, Path: u256.Zero(), Instruction: z.Instruction{Version: z.INSTR_VERSION_0, Opcode: z.OP_FORWARD, Operand: operand}})
	if err != nil {
		panic(err)
	}
	return data
}

func mustZkgmPacketData(packet z.ZkgmPacket) []byte {
	data, err := z.EncodeZkgmPacket(packet)
	if err != nil {
		panic(err)
	}
	return data
}

// Output:
// [SCENARIO] 1. Bootstrap and open the parent (1) and child source (2) channels
//
// [SCENARIO] 2. A forward with an allowed OP_CALL child is accepted (parked async)
// [INFO] valid forward  -> parent receipt: committed, child commitment: committed
// [EXPECTED] committed: parent parked in-flight, child relayed, ack deferred until the child resolves
//
// [SCENARIO] 3. A forward with an allowed OP_TOKEN_ORDER child is accepted (parked async)
// [INFO] token child    -> parent receipt: committed, child commitment: committed
// [EXPECTED] committed: TokenOrder child is relayed as the forward child packet
//
// [SCENARIO] 4. A forward with an allowed OP_BATCH child is accepted (parked async)
// [INFO] batch child    -> parent receipt: committed, child commitment: committed
// [EXPECTED] committed: Batch child is relayed as the forward child packet
//
// [SCENARIO] 5. A forward with a nested OP_FORWARD child is rejected (synchronous failure ack)
// [INFO] nested forward -> parent receipt: ack-written, would-be child commitment: none
// [EXPECTED] ack-written: rejected by the child allowlist, would-be child absent, parent not in-flight
