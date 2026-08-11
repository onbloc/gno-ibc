// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/forward
package forward

// forward_recv_async_lifecycle_filetest pins OP_FORWARD receive semantics:
// malformed forward paths write synchronous failure acks, while valid forwards
// are asynchronous. recv records only the parent receipt and sends the child
// packet; the child timeout later writes the deferred parent ack. Also
// verifies the parent ack's exact bytes (via CommitAcks hash comparison, the
// only way to check ack content — the store keeps just a commitment) against
// the child's success ack, failure ack, and the timeout's universalErrorAck(),
// not just that some ack was written.

import (
	"chain"
	"testing"

	"gno.land/p/nt/ufmt/v0"
	"gno.land/p/onbloc/ibc/union/types"
	z "gno.land/p/onbloc/ibc/union/zkgm"

	u256 "gno.land/p/onbloc/math/uint256"

	"gno.land/r/onbloc/ibc/union/access"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	_ "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"

	"gno.land/r/onbloc/ibc/union/core"
	_ "gno.land/r/onbloc/ibc/union/core/v1"

	mocklc "gno.land/r/onbloc/ibc/testing/mock/lightclient"
)

const (
	coreImplPath  = "gno.land/r/onbloc/ibc/union/core/v1"
	zkgmImplPath  = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	mockLcPkgPath = "gno.land/r/onbloc/ibc/testing/mock/lightclient"

	adminAddr = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
)

func main(cur realm) {
	println("[SCENARIO] 1. Bootstrap IBC host and open a zkgm channel")
	channelId := bootstrap(cur)
	println("")

	println("[SCENARIO] 2. Invalid OP_FORWARD writes a sync failure acknowledgement")
	invalidForwardWritesFailureAck(cur, channelId)
	println("")

	println("[SCENARIO] 3. Valid OP_FORWARD defers parent acknowledgement until child timeout")
	validForwardDefersUntilChildTimeout(cur, channelId)
	println("")

	println("[SCENARIO] 4. Valid OP_FORWARD child acknowledgement resolves parent acknowledgement")
	validForwardDefersUntilChildAck(cur, channelId)
	println("")

	println("[SCENARIO] 5. Valid OP_FORWARD child failure acknowledgement resolves parent acknowledgement")
	validForwardDefersUntilChildFailureAck(cur, channelId)
	println("")

	println("[SCENARIO] 6. Multi-hop OP_FORWARD emits a continuation child packet")
	multiHopForwardBuildsContinuationChild(cur, channelId)
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
	return channelId
}

func invalidForwardWritesFailureAck(cur realm, channelId types.ChannelId) {
	parent := forwardPacket(channelId, [32]byte{0x01}, forwardPath(uint32(channelId)))

	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{parent}, [][]byte{nil}, nil, 1))

	ufmt.Printf("[INFO] invalid forward parent sync ack written: %t\n", ackWritten(parent))
	ufmt.Println("[EXPECTED] malformed forward path is rejected with a sync failure ack")
}

func validForwardDefersUntilChildTimeout(cur realm, channelId types.ChannelId) {
	salt := [32]byte{0x02}
	parent := forwardPacket(channelId, salt, forwardPath(uint32(channelId), uint32(channelId)))
	child := forwardedChildPacket(channelId, salt)

	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{parent}, [][]byte{nil}, nil, 1))
	ufmt.Printf("[INFO] valid forward parent is receipt-only after recv: %t\n", receiptOnly(parent))

	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketTimeout(cross(cur), types.NewMsgPacketTimeout(child, nil, 1))
	ufmt.Printf("[INFO] valid forward parent ack written after child timeout: %t\n", ackWritten(parent))
	// handleForwardChild (forward.gno:161) writes the child timeout's parent ack
	// as universalErrorAck() verbatim (OnTimeoutPacket, impl.gno:161) — not a
	// transformed or wrapped value.
	ufmt.Printf("[INFO] parent ack bytes equal universalErrorAck(): %t\n", parentAckEquals(parent, universalErrorAck()))
	ufmt.Println("[EXPECTED] valid forward recv is async; the child timeout resolves the parent ack")
	ufmt.Println("[EXPECTED] parent ack should be byte-identical to universalErrorAck() (tag+inner preserved)")
}

func validForwardDefersUntilChildAck(cur realm, channelId types.ChannelId) {
	salt := [32]byte{0x03}
	parent := forwardPacket(channelId, salt, forwardPath(uint32(channelId), uint32(channelId)))
	child := forwardedChildPacket(channelId, salt)

	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{parent}, [][]byte{nil}, nil, 1))
	ufmt.Printf("[INFO] valid forward parent is receipt-only after recv: %t\n", receiptOnly(parent))

	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketAcknowledgement(cross(cur), core.NewMsgPacketAcknowledgement([]types.Packet{child}, [][]byte{successAck()}, nil, 1))
	ufmt.Printf("[INFO] valid forward parent ack written after child ack: %t\n", ackWritten(parent))
	// handleForwardChild (forward.gno:74) passes the child's raw acknowledgement
	// bytes straight through to WriteAcknowledgement — no re-encoding.
	ufmt.Printf("[INFO] parent ack bytes equal child success ack: %t\n", parentAckEquals(parent, successAck()))
	ufmt.Println("[EXPECTED] valid forward child ack resolves the deferred parent ack")
	ufmt.Println("[EXPECTED] parent ack should be byte-identical to the child's success ack (tag+inner preserved)")
}

// validForwardDefersUntilChildFailureAck is the FAILURE-ack counterpart to
// validForwardDefersUntilChildAck: the child settles with a business-level
// failure ack (not a timeout, not a panic), and the parent ack must carry
// that exact FAILURE tag and inner bytes through, not a universalErrorAck()
// substitute.
func validForwardDefersUntilChildFailureAck(cur realm, channelId types.ChannelId) {
	salt := [32]byte{0x05}
	parent := forwardPacket(channelId, salt, forwardPath(uint32(channelId), uint32(channelId)))
	child := forwardedChildPacket(channelId, salt)

	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{parent}, [][]byte{nil}, nil, 1))
	ufmt.Printf("[INFO] valid forward parent is receipt-only after recv: %t\n", receiptOnly(parent))

	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketAcknowledgement(cross(cur), core.NewMsgPacketAcknowledgement([]types.Packet{child}, [][]byte{failureAck()}, nil, 1))
	ufmt.Printf("[INFO] valid forward parent ack written after child failure ack: %t\n", ackWritten(parent))
	ufmt.Printf("[INFO] parent ack bytes equal child failure ack: %t\n", parentAckEquals(parent, failureAck()))
	ufmt.Printf("[INFO] parent ack bytes equal universalErrorAck() (should not be): %t\n", parentAckEquals(parent, universalErrorAck()))
	ufmt.Println("[EXPECTED] valid forward child failure ack resolves the deferred parent ack")
	ufmt.Println("[EXPECTED] parent ack should be byte-identical to the child's failure ack (tag+inner preserved), not the universal-error substitute")
}

func multiHopForwardBuildsContinuationChild(cur realm, channelId types.ChannelId) {
	salt := [32]byte{0x04}
	path := forwardPath(uint32(channelId), uint32(channelId), uint32(types.ChannelId(2)), uint32(channelId))
	parent := forwardPacket(channelId, salt, path)
	child := forwardedContinuationChildPacket(channelId, salt)

	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{parent}, [][]byte{nil}, nil, 1))
	zp := mustDecodeZkgmPacket(child)

	ufmt.Printf("[INFO] multi-hop parent is receipt-only after recv: %t\n", receiptOnly(parent))
	ufmt.Printf("[INFO] multi-hop child packet committed: %t\n", packetCommitted(child))
	ufmt.Printf("[INFO] multi-hop child opcode is OP_FORWARD: %t\n", zp.Instruction.Opcode == z.OP_FORWARD)
	ufmt.Printf("[INFO] multi-hop child salt is derived: %t\n", zp.Salt == z.DeriveForwardSalt(salt))
	ufmt.Printf("[INFO] multi-hop child source channel is expected: %t\n", child.SourceChannelId == channelId)
	ufmt.Printf("[INFO] multi-hop child destination channel is expected: %t\n", child.DestinationChannelId == types.ChannelId(2))
	ufmt.Println("[EXPECTED] continuation paths keep forwarding instead of executing the final child")
}

func forwardPacket(channelId types.ChannelId, salt [32]byte, forwardPath *u256.Uint) types.Packet {
	data, err := z.EncodeZkgmPacket(z.ZkgmPacket{
		Salt: salt,
		Path: u256.Zero(),
		Instruction: z.Instruction{
			Version: z.INSTR_VERSION_0,
			Opcode:  z.OP_FORWARD,
			Operand: mustForwardBytes(z.Forward{
				Path:             forwardPath,
				TimeoutTimestamp: 1,
				Instruction:      callInstruction(),
			}),
		},
	})
	if err != nil {
		panic(err)
	}

	return core.NewPacket(types.ChannelId(2), channelId, data, types.Timestamp(1<<62))
}

func forwardedChildPacket(channelId types.ChannelId, parentSalt [32]byte) types.Packet {
	childPath := forwardPath(uint32(channelId), uint32(channelId))
	data, err := z.EncodeZkgmPacket(z.ZkgmPacket{
		Salt:        z.DeriveForwardSalt(parentSalt),
		Path:        childPath,
		Instruction: callInstruction(),
	})
	if err != nil {
		panic(err)
	}

	return core.NewPacket(channelId, types.ChannelId(2), data, types.Timestamp(1))
}

func forwardedContinuationChildPacket(channelId types.ChannelId, parentSalt [32]byte) types.Packet {
	childPath := forwardPath(uint32(channelId), uint32(channelId))
	continuationPath := forwardPath(uint32(types.ChannelId(2)), uint32(channelId))
	data, err := z.EncodeZkgmPacket(z.ZkgmPacket{
		Salt: z.DeriveForwardSalt(parentSalt),
		Path: childPath,
		Instruction: z.Instruction{
			Version: z.INSTR_VERSION_0,
			Opcode:  z.OP_FORWARD,
			Operand: mustForwardBytes(z.Forward{
				Path:             continuationPath,
				TimeoutTimestamp: 1,
				Instruction:      callInstruction(),
			}),
		},
	})
	if err != nil {
		panic(err)
	}

	return core.NewPacket(channelId, types.ChannelId(2), data, types.Timestamp(1))
}

func callInstruction() z.Instruction {
	callBytes, err := z.EncodeCall(z.Call{
		Sender:           []byte("remote-sender"),
		ContractAddress:  []byte("gno.land/r/onbloc/ibc/testing/mock/receiver"),
		ContractCalldata: []byte("forward-child"),
	})
	if err != nil {
		panic(err)
	}

	return z.Instruction{Version: z.INSTR_VERSION_0, Opcode: z.OP_CALL, Operand: callBytes}
}

func successAck() []byte {
	ack, err := z.EncodeAck(z.Ack{Tag: z.Uint256FromBytes32(z.TAG_ACK_SUCCESS), InnerAck: []byte("child-ok")})
	if err != nil {
		panic(err)
	}

	return ack
}

func failureAck() []byte {
	ack, err := z.EncodeAck(z.Ack{Tag: z.Uint256FromBytes32(z.TAG_ACK_FAILURE), InnerAck: []byte("child-rejected")})
	if err != nil {
		panic(err)
	}

	return ack
}

// universalErrorAck mirrors the v1 impl's unexported universalErrorAck()
// (dispatch.gno): Ack{Tag: 0, InnerAck: empty}, ABI-encoded. handleForwardChild
// writes this verbatim as the parent ack on a child timeout.
func universalErrorAck() []byte {
	ack, err := z.EncodeAck(z.Ack{Tag: u256.Zero(), InnerAck: []byte{}})
	if err != nil {
		panic(err)
	}

	return ack
}

// parentAckEquals reports whether the parent packet's settled acknowledgement
// is byte-identical to expectedAck. Only the ack's commitment (a hash) is
// ever stored, never the plaintext, so the comparison recomputes the same
// hash locally via types.CommitAcks and compares commitments — exact and
// non-brittle, unlike matching the full recv event list.
func parentAckEquals(parent types.Packet, expectedAck []byte) bool {
	commitment, err := core.GetBatchReceipts(core.CommitPacketHash(parent))
	if err != nil {
		return false
	}

	return commitment == types.CommitAcks([][]byte{expectedAck})
}

func mustForwardBytes(forward z.Forward) []byte {
	out, err := z.EncodeForward(forward)
	if err != nil {
		panic(err)
	}

	return out
}

func forwardPath(channels ...uint32) *u256.Uint {
	path := u256.Zero()
	for _, channel := range channels {
		var err error
		path, err = z.UpdateChannelPath(path, channel)
		if err != nil {
			panic(err)
		}
	}
	return path
}

func receiptOnly(packet types.Packet) bool {
	commitment, err := core.GetBatchReceipts(core.CommitPacketHash(packet))
	return err == nil && commitment == types.COMMITMENT_MAGIC
}

func ackWritten(packet types.Packet) bool {
	commitment, err := core.GetBatchReceipts(core.CommitPacketHash(packet))
	return err == nil && commitment != types.COMMITMENT_MAGIC
}

func packetCommitted(packet types.Packet) bool {
	commitment, err := core.GetBatchPackets(core.CommitPacketHash(packet))
	return err == nil && commitment == types.COMMITMENT_MAGIC
}

func mustDecodeZkgmPacket(packet types.Packet) z.ZkgmPacket {
	zp, err := z.DecodeZkgmPacket(types.CloneBytes(packet.Data))
	if err != nil {
		panic(err)
	}

	return zp
}

// Output:
// [SCENARIO] 1. Bootstrap IBC host and open a zkgm channel
//
// [SCENARIO] 2. Invalid OP_FORWARD writes a sync failure acknowledgement
// [INFO] invalid forward parent sync ack written: true
// [EXPECTED] malformed forward path is rejected with a sync failure ack
//
// [SCENARIO] 3. Valid OP_FORWARD defers parent acknowledgement until child timeout
// [INFO] valid forward parent is receipt-only after recv: true
// [INFO] valid forward parent ack written after child timeout: true
// [INFO] parent ack bytes equal universalErrorAck(): true
// [EXPECTED] valid forward recv is async; the child timeout resolves the parent ack
// [EXPECTED] parent ack should be byte-identical to universalErrorAck() (tag+inner preserved)
//
// [SCENARIO] 4. Valid OP_FORWARD child acknowledgement resolves parent acknowledgement
// [INFO] valid forward parent is receipt-only after recv: true
// [INFO] valid forward parent ack written after child ack: true
// [INFO] parent ack bytes equal child success ack: true
// [EXPECTED] valid forward child ack resolves the deferred parent ack
// [EXPECTED] parent ack should be byte-identical to the child's success ack (tag+inner preserved)
//
// [SCENARIO] 5. Valid OP_FORWARD child failure acknowledgement resolves parent acknowledgement
// [INFO] valid forward parent is receipt-only after recv: true
// [INFO] valid forward parent ack written after child failure ack: true
// [INFO] parent ack bytes equal child failure ack: true
// [INFO] parent ack bytes equal universalErrorAck() (should not be): false
// [EXPECTED] valid forward child failure ack resolves the deferred parent ack
// [EXPECTED] parent ack should be byte-identical to the child's failure ack (tag+inner preserved), not the universal-error substitute
//
// [SCENARIO] 6. Multi-hop OP_FORWARD emits a continuation child packet
// [INFO] multi-hop parent is receipt-only after recv: true
// [INFO] multi-hop child packet committed: true
// [INFO] multi-hop child opcode is OP_FORWARD: true
// [INFO] multi-hop child salt is derived: true
// [INFO] multi-hop child source channel is expected: true
// [INFO] multi-hop child destination channel is expected: true
// [EXPECTED] continuation paths keep forwarding instead of executing the final child
