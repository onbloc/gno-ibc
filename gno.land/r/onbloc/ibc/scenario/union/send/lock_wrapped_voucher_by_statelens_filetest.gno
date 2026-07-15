// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/send
package send

// lock_wrapped_voucher_by_statelens_filetest funds a sender, escrows (locks) a ucs03-zkgm
// voucher, then acknowledges the sent packet with an acknowledgement proven by the
// real state-lens/ics23-mpt light client, asserting the escrow stays locked. The
// funding recv and the ack prove different commitments, so they use two consensus
// heights: the fund height is seeded at client creation and the ack height is added
// with a crafted UpdateClient header. Both MPT proofs are built inline.

import (
	"encoding/hex"
	"crypto/keccak256"
	"testing"

	"gno.land/p/onbloc/encoding/rlp"
	"gno.land/p/onbloc/ibc/union/lightclient"
	ics23mpt "gno.land/p/onbloc/ibc/union/lightclient/state_lens/ics23_mpt"
	types "gno.land/p/onbloc/ibc/union/types"
	"gno.land/p/onbloc/verifier/evm/storage"

	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/ufmt/v0"
	z "gno.land/p/onbloc/ibc/union/zkgm"

	"gno.land/r/onbloc/ibc/union/access"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	_ "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1" // install zkgm v1 impl (init registers the constructor)
	core "gno.land/r/onbloc/ibc/union/core"
	_ "gno.land/r/onbloc/ibc/union/core/v1"
)

const (
	coreImplPath = "gno.land/r/onbloc/ibc/union/core/v1"
	zkgmImplPath = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"

	adminAddr  = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
	senderAddr = address("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm")

	fundHeight = uint64(100)
	ackHeight  = uint64(200)
)

func main(cur realm) {
	fx := buildSendFixture()

	println("[SCENARIO] 1. Open a state-lens-backed channel and fund the sender via a proven recv")
	clientId := openAndFundSender(cur, fx.fundRoot, fx.initPacket, fx.fundProof, fx.counterpartyChannel, fx.quoteToken)
	println("")

	println("[SCENARIO] 2. Send ESCROW order locking 40 of the voucher")
	sendPacket := sendEscrowOrder(cur, fx.channelId, fx.quoteToken)
	println("")

	println("[SCENARIO] 3. Acknowledge the sent packet with a state-lens MPT proof (escrow no-op)")
	acknowledgeWithProof(cur, clientId, sendPacket, fx.quoteToken)
}

// sendFixture holds the deterministic funding packet, its proof, and the storage
// root the scenario builds up front and threads through its steps.
type sendFixture struct {
	channelId           types.ChannelId
	counterpartyChannel types.ChannelId
	fundRoot            []byte
	initPacket          types.Packet
	fundProof           []byte
	quoteToken          string
}

// buildSendFixture builds the deterministic funding packet and the single-leaf
// EVM-MPT proof + storage root that commits it. The first channel opened is
// ChannelId(1), so the wrapped denom and the packet are known up front.
func buildSendFixture() sendFixture {
	channelId := types.ChannelId(1)
	counterpartyChannel := types.ChannelId(2)
	meta := mustTokenMetadata("af739f34ddf951cbc24fdbba4f76213688e13627", z.TokenInitializer{Name: "Gno Token", Symbol: "GNOT", Decimals: 6})
	quoteToken := z.PredictWrappedTokenV2(u256.Zero(), uint32(channelId), []byte("ugnot"), z.MetadataImage(mustDecodeMeta(meta)))
	initOrder := z.TokenOrderV2{
		Sender:      []byte("remote-sender"),
		Receiver:    []byte(senderAddr.String()),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(100),
		QuoteToken:  []byte(quoteToken),
		QuoteAmount: u256.NewUint(100),
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
		Metadata:    meta,
	}
	initPacket := core.NewPacket(counterpartyChannel, channelId, mustPacketData(mustOrderInstruction(initOrder)), types.Timestamp(1<<62))
	fundRoot, fundProof := buildMembershipProof(types.BatchPacketsPath(core.CommitPacketsHash([]types.Packet{initPacket})), commitmentMagic())

	return sendFixture{
		channelId:           channelId,
		counterpartyChannel: counterpartyChannel,
		fundRoot:            fundRoot,
		initPacket:          initPacket,
		fundProof:           fundProof,
		quoteToken:          quoteToken,
	}
}

// openAndFundSender installs the impls, registers the mock L1 and the real
// state-lens client (seeding its fund-height consensus with fundRoot), Force-opens
// the connection/channel, and receives the proven funding packet. It returns the
// state-lens client id.
//
// It is kept inline (not split further): every admin/relayer core entrypoint
// authorizes the caller via cur.Previous(), so testing.SetRealm and the cross(cur)
// call must run in the same frame for the admin user to be seen as the caller.
func openAndFundSender(cur realm, fundRoot []byte, initPacket types.Packet, fundProof []byte, counterpartyChannel types.ChannelId, quoteToken string) types.ClientId {
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.UpdateImpl(cross(cur), coreImplPath)
	zkgm.UpdateImpl(cross(cur), zkgmImplPath)
	zkgm.SetRateLimitDisabled(cross(cur), true)
	zkgm.RegisterCoreApp(cross(cur))
	access.GrantRole(cross(cur), access.RelayerRole, adminAddr)

	clientState := &ics23mpt.ClientState{
		L2ChainID:         "l2-chain",
		L1ClientID:        1,
		L2ClientID:        7,
		L2LatestHeight:    fundHeight,
		TimestampOffset:   64,
		StateRootOffset:   0,
		StorageRootOffset: 32,
	}
	consensusState := &ics23mpt.ConsensusState{Timestamp: 1, StateRoot: make([]byte, 32), StorageRoot: fundRoot}
	clientStateBytes, err := ics23mpt.EncodeClientState(*clientState)
	if err != nil {
		panic(err)
	}
	consensusStateBytes, err := ics23mpt.EncodeConsensusState(*consensusState)
	if err != nil {
		panic(err)
	}

	// Register a mock L1 client first — state lens needs its L1ClientID resolved in the store.
	mockL1Type := types.ClientType("mock-l1")
	core.RegisterClient(cross(cur), mockL1Type, func(_, _ []byte) (lightclient.Interface, error) {
		return &mockL1Client{}, nil
	})
	core.CreateClient(cross(cur), core.NewMsgCreateClient(mockL1Type, nil, nil))

	clientType := types.ClientType(ics23mpt.ClientType)
	core.RegisterClient(cross(cur), clientType, func(csBytes, consBytes []byte) (lightclient.Interface, error) {
		cs, err := ics23mpt.DecodeClientState(csBytes)
		if err != nil {
			return nil, err
		}
		cons, err := ics23mpt.DecodeConsensusState(consBytes)
		if err != nil {
			return nil, err
		}
		return ics23mpt.NewStateLensIcs23MptLightClient(&cs, &cons, core.GetLightClient)
	})
	core.CreateClient(cross(cur), core.NewMsgCreateClient(clientType, clientStateBytes, consensusStateBytes))
	clientId := types.ClientId(2)

	core.ConnectionOpenInit(cross(cur), core.NewMsgConnectionOpenInit(clientId, types.ClientId(99)))
	connectionId := types.ConnectionId(1)
	core.ForceConnectionOpenAck(cross(cur), core.NewMsgConnectionOpenAck(connectionId, types.ConnectionId(77), nil, 0))

	portId := []byte(zkgm.ProxyPkgPath())
	core.ChannelOpenInit(cross(cur), core.NewMsgChannelOpenInit(portId, portId, connectionId, zkgm.Version, "g1relayer"))
	opened := types.ChannelId(1)
	core.ForceChannelOpenAck(cross(cur), core.NewMsgChannelOpenAck(opened, zkgm.Version, counterpartyChannel, nil, 0, "g1relayer"))

	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{initPacket}, [][]byte{nil}, fundProof, fundHeight))
	ufmt.Printf("[INFO] sender voucher balance after fund: %d\n", zkgm.VoucherBalanceOf(quoteToken, senderAddr))
	ufmt.Println("[EXPECTED] sender voucher balance after fund should be 100")

	return clientId
}

// sendEscrowOrder sends an ESCROW TokenOrder that locks 40 of the voucher into the
// proxy escrow, and returns the produced packet for later acknowledgement.
func sendEscrowOrder(cur realm, channelId types.ChannelId, quoteToken string) types.Packet {
	order := z.TokenOrderV2{
		Sender:      []byte(senderAddr.String()),
		Receiver:    []byte("remote-receiver"),
		BaseToken:   []byte(quoteToken),
		BaseAmount:  u256.NewUint(40),
		QuoteToken:  []byte("ugnot"),
		QuoteAmount: u256.NewUint(40),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}

	testing.SetRealm(testing.NewUserRealm(senderAddr))
	sendPacket := zkgm.Send(cross(cur), channelId, types.Timestamp(1<<62), [32]byte{}, mustOrderInstruction(order))

	ufmt.Printf("[INFO] sender voucher balance after send: %d\n", zkgm.VoucherBalanceOf(quoteToken, senderAddr))
	ufmt.Printf("[INFO] proxy escrow balance after send: %d\n", zkgm.VoucherBalanceOf(quoteToken, zkgm.ProxyAddress()))
	ufmt.Println("[EXPECTED] sender voucher balance after send should be 60 (100 - 40 escrowed)")
	ufmt.Println("[EXPECTED] proxy escrow balance after send should be 40 (locked)")

	return sendPacket
}

// acknowledgeWithProof adds the ack-height consensus via a crafted UpdateClient
// header, then acknowledges the sent packet with the inline state-lens MPT proof.
// The protocol-fill ack is a no-op for an escrow, so the lock holds.
func acknowledgeWithProof(cur realm, clientId types.ClientId, sendPacket types.Packet, quoteToken string) {
	ack := mustSuccessAck(mustProtocolTokenOrderAck())
	ackCommitment := types.CommitAcks([][]byte{ack})
	ackRoot, ackProof := buildMembershipProof(types.BatchReceiptsPath(core.CommitPacketsHash([]types.Packet{sendPacket})), ackCommitment[:])

	testing.SetRealm(testing.NewUserRealm(adminAddr))
	header := ics23mpt.Header{
		L1Height:              fundHeight,
		L2Height:              ackHeight,
		L2ConsensusStateProof: []byte("l1-proof"),
		L2ConsensusState:      makeConsensusBytes(2, make([]byte, 32), ackRoot),
	}
	headerBytes, err := ics23mpt.EncodeHeader(header)
	if err != nil {
		panic(err)
	}
	core.UpdateClient(cross(cur), types.NewMsgUpdateClient(clientId, headerBytes))

	core.PacketAcknowledgement(cross(cur), core.NewMsgPacketAcknowledgement([]types.Packet{sendPacket}, [][]byte{ack}, ackProof, ackHeight))

	ufmt.Printf("[INFO] sender voucher balance after ack: %d\n", zkgm.VoucherBalanceOf(quoteToken, senderAddr))
	ufmt.Printf("[INFO] proxy escrow balance after ack: %d\n", zkgm.VoucherBalanceOf(quoteToken, zkgm.ProxyAddress()))
	ufmt.Println("[EXPECTED] sender voucher balance after ack should be 60 (unchanged: escrow stays locked)")
	ufmt.Println("[EXPECTED] proxy escrow balance after ack should be 40 (unchanged: escrow stays locked)")
}

func commitmentMagic() []byte {
	magic := types.COMMITMENT_MAGIC
	return magic[:]
}

// buildMembershipProof returns (storageRoot, encodedProof) for a single-leaf
// EVM-MPT proving that commitmentPath stores value. Mirrors storageProofFixture
// in the state-lens client's client_test.gno.
func buildMembershipProof(commitmentPath types.H256, value []byte) ([]byte, []byte) {
	slot, err := storage.IBCCommitmentKey(commitmentPath[:])
	if err != nil {
		panic(err)
	}

	storedValue, err := storage.EncodeStorageValue(value)
	if err != nil {
		panic(err)
	}

	storagePath, err := storage.StoragePath(slot[:])
	if err != nil {
		panic(err)
	}

	leaf := rlp.EncodeList(rlp.EncodeBytes(compactEncode(true, nibbles(storagePath[:]))), rlp.EncodeBytes(storedValue))
	root := keccak256.Sum256(leaf)

	proof := storage.EncodeProof(storage.Proof{Key: slot[:], Value: value, Proof: [][]byte{leaf}})

	return root[:], proof
}

// makeConsensusBytes lays out an L2 consensus blob matching the client offsets
// (state_root@0, storage_root@32, big-endian timestamp@64). Copied from the
// state-lens client_test.gno helper.
func makeConsensusBytes(timestamp uint64, stateRoot, storageRoot []byte) []byte {
	out := make([]byte, 72)
	copy(out[0:32], stateRoot)
	copy(out[32:64], storageRoot)
	out[64] = byte(timestamp >> 56)
	out[65] = byte(timestamp >> 48)
	out[66] = byte(timestamp >> 40)
	out[67] = byte(timestamp >> 32)
	out[68] = byte(timestamp >> 24)
	out[69] = byte(timestamp >> 16)
	out[70] = byte(timestamp >> 8)
	out[71] = byte(timestamp)

	return out
}

// nibbles and compactEncode are copied verbatim from the state-lens client's
// client_test.gno (test-only, unexported); they build the MPT leaf path.
func nibbles(key []byte) []byte {
	out := make([]byte, 0, len(key)*2)
	for _, b := range key {
		out = append(out, b>>4, b&0x0f)
	}

	return out
}

func compactEncode(leaf bool, ns []byte) []byte {
	flag := byte(0)
	if leaf {
		flag = 2
	}

	odd := len(ns)%2 == 1
	out := make([]byte, 0, (len(ns)+2)/2)

	if odd {
		out = append(out, (flag+1)<<4|ns[0])
		ns = ns[1:]
	} else {
		out = append(out, flag<<4)
	}

	for i := 0; i < len(ns); i += 2 {
		out = append(out, ns[i]<<4|ns[i+1])
	}

	return out
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

func mustTokenMetadata(implementationHex string, ti z.TokenInitializer) []byte {
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

func mustDecodeMeta(bz []byte) z.TokenMetadata {
	meta, err := z.DecodeTokenMetadata(bz)
	if err != nil {
		panic(err)
	}
	return meta
}

func mustProtocolTokenOrderAck() []byte {
	bz, err := z.EncodeTokenOrderAck(z.TokenOrderAck{FillType: new(u256.Uint).SetBytes(z.FILL_TYPE_PROTOCOL[:])})
	if err != nil {
		panic(err)
	}
	return bz
}

func mustSuccessAck(inner []byte) []byte {
	ack, err := z.EncodeAck(z.Ack{Tag: new(u256.Uint).SetBytes(z.TAG_ACK_SUCCESS[:]), InnerAck: inner})
	if err != nil {
		panic(err)
	}
	return ack
}

// --- minimal L1 light client stub ---

type mockL1Client struct{}

func (m *mockL1Client) VerifyMembership(uint64, []byte, []byte, []byte) error { return nil }
func (m *mockL1Client) VerifyNonMembership(uint64, []byte, []byte) error      { return nil }
func (m *mockL1Client) GetTimestamp() types.Timestamp                         { return types.Timestamp(1) }

func (m *mockL1Client) GetTimestampAtHeight(uint64) (types.Timestamp, error) {
	return types.Timestamp(1), nil
}
func (m *mockL1Client) GetLatestHeight() uint64        { return ackHeight }
func (m *mockL1Client) GetCounterpartyChainID() string { return "l1" }
func (m *mockL1Client) Status() lightclient.Status     { return lightclient.Active }

func (m *mockL1Client) VerifyHeader(_ address, header []byte, _ address) (types.StateUpdate, error) {
	return types.StateUpdate{Height: ackHeight}, nil
}

func (m *mockL1Client) VerifyCreation(address, address) (types.ClientCreationResult, error) {
	return types.ClientCreationResult{}, nil
}

func (m *mockL1Client) Misbehaviour(address, []byte, address) ([]byte, error) {
	return nil, errL1Unsupported
}

var errL1Unsupported = mockError("mock l1: unsupported")

type mockError string

func (e mockError) Error() string { return string(e) }

// Output:
// [SCENARIO] 1. Open a state-lens-backed channel and fund the sender via a proven recv
// [INFO] sender voucher balance after fund: 100
// [EXPECTED] sender voucher balance after fund should be 100
//
// [SCENARIO] 2. Send ESCROW order locking 40 of the voucher
// [INFO] sender voucher balance after send: 60
// [INFO] proxy escrow balance after send: 40
// [EXPECTED] sender voucher balance after send should be 60 (100 - 40 escrowed)
// [EXPECTED] proxy escrow balance after send should be 40 (locked)
//
// [SCENARIO] 3. Acknowledge the sent packet with a state-lens MPT proof (escrow no-op)
// [INFO] sender voucher balance after ack: 60
// [INFO] proxy escrow balance after ack: 40
// [EXPECTED] sender voucher balance after ack should be 60 (unchanged: escrow stays locked)
// [EXPECTED] proxy escrow balance after ack should be 40 (unchanged: escrow stays locked)
