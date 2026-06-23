// PKGPATH: gno.land/r/onbloc/ibc/scenario/union
package union

// token_receive_by_statelens_filetest receives a ucs03-zkgm token packet proven by
// the real state-lens/ics23-mpt light client. It builds a single-leaf EVM-MPT
// storage proof inline (no exported builder exists), seeds the client's consensus
// storage root with it, Force-opens the handshake, and asserts the host mints the
// wrapped voucher to the receiver.

import (
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

	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	impl "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	core "gno.land/r/onbloc/ibc/union/core"
	_ "gno.land/r/onbloc/ibc/union/core/v1"
)

const (
	coreImplPath = "gno.land/r/onbloc/ibc/union/core/v1"
	zkgmImplPath = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"

	adminAddr    = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
	receiverAddr = address("g1dyxy88p94acjnm8dmu9tfj2mv2ncvx83cagllu")

	statelensProofHeight = uint64(100)
)

func main(cur realm) {
	// --- SCENARIO 1: install impls, build the proof, open a state-lens channel ---
	ufmt.Println("[SCENARIO] 1. Open a channel backed by the real state-lens/ics23-mpt light client")
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.UpdateImpl(cross(cur), coreImplPath)
	zkgm.UpdateImpl(cross(cur), zkgmImplPath)
	zkgm.SetRateLimitDisabled(cross(cur), true)
	zkgm.RegisterCoreApp(cross(cur))

	// The first channel opened is ChannelId(1); the wrapped denom and the packet
	// are deterministic, so the packet (and its commitment) can be built up front.
	channelId := types.ChannelId(1)
	sourceChannel := types.ChannelId(2)
	meta := mustTokenMetadata("grc20", z.TokenInitializer{Name: "Gno Token", Symbol: "GNOT", Decimals: 6})
	quoteToken := impl.PredictWrappedTokenV2(u256.Zero(), uint32(channelId), []byte("ugnot"), impl.MetadataImage(mustDecodeMeta(meta)))
	order := z.TokenOrderV2{
		Sender:      []byte("remote-sender"),
		Receiver:    []byte(receiverAddr.String()),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(100),
		QuoteToken:  []byte(quoteToken),
		QuoteAmount: u256.NewUint(100),
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
		Metadata:    meta,
	}
	packet := core.NewPacket(sourceChannel, channelId, mustPacketData(mustOrderInstruction(order)), types.Timestamp(1<<62))

	// Build the EVM-MPT storage proof for this packet's commitment and the storage
	// root that commits it; the client's consensus state is seeded with that root.
	storageRoot, packetProof := buildPacketMembershipProof(packet)

	clientState := &ics23mpt.ClientState{
		L2ChainID:         "l2-chain",
		L1ClientID:        1,
		L2ClientID:        7,
		L2LatestHeight:    statelensProofHeight,
		TimestampOffset:   64,
		StateRootOffset:   0,
		StorageRootOffset: 32,
	}
	consensusState := &ics23mpt.ConsensusState{
		Timestamp:   1,
		StateRoot:   make([]byte, 32),
		StorageRoot: storageRoot,
	}
	lc, err := ics23mpt.NewStateLensIcs23MptLightClient(clientState, consensusState, &mockL1Client{})
	if err != nil {
		panic(err)
	}

	clientStateBytes, err := ics23mpt.EncodeClientState(*clientState)
	if err != nil {
		panic(err)
	}
	consensusStateBytes, err := ics23mpt.EncodeConsensusState(*consensusState)
	if err != nil {
		panic(err)
	}

	clientType := types.ClientType(ics23mpt.ClientType)
	core.RegisterClient(cross(cur), clientType, lc)
	core.CreateClient(cross(cur), core.NewMsgCreateClient(clientType, clientStateBytes, consensusStateBytes))
	clientId := types.ClientId(1)

	// Force-open connection + channel (admin variants skip the handshake proofs).
	core.ConnectionOpenInit(cross(cur), core.NewMsgConnectionOpenInit(clientId, types.ClientId(99)))
	connectionId := types.ConnectionId(1)
	core.ForceConnectionOpenAck(cross(cur), core.NewMsgConnectionOpenAck(connectionId, types.ConnectionId(77), nil, 0))

	portId := []byte(zkgm.ProxyPkgPath())
	core.ChannelOpenInit(cross(cur), core.NewMsgChannelOpenInit(portId, portId, connectionId, zkgm.Version, "g1relayer"))
	opened := types.ChannelId(1)
	core.ForceChannelOpenAck(cross(cur), core.NewMsgChannelOpenAck(opened, zkgm.Version, sourceChannel, nil, 0, "g1relayer"))

	ufmt.Printf("[INFO] client opened: id=%s type=%s\n", clientId.String(), ics23mpt.ClientType)
	ufmt.Printf("[INFO] channel opened (source=%s destination=%s)\n", sourceChannel.String(), opened.String())
	ufmt.Println("[EXPECTED] client type should be state-lens/ics23/mpt (real, not mock)")
	ufmt.Println("[EXPECTED] destination channel should be 1")

	// --- SCENARIO 2: receive the packet proven by the state-lens MPT proof ---
	ufmt.Println("")
	ufmt.Println("[SCENARIO] 2. Receive INITIALIZE order proven by the state-lens MPT proof (mint 100)")
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{packet}, nil, packetProof, statelensProofHeight))

	_, receiptRecorded := core.GetBatchReceipts(core.CommitPacketsHash([]types.Packet{packet}))
	ufmt.Printf("[INFO] packet receipt recorded (state-lens MPT proof verified): %t\n", receiptRecorded)
	ufmt.Printf("[INFO] minted token (wrapped voucher): %s\n", quoteToken)
	ufmt.Printf("[INFO] receiver voucher balance: %d\n", zkgm.VoucherBalanceOf(quoteToken, receiverAddr))
	ufmt.Println("[EXPECTED] packet receipt recorded (state-lens MPT proof verified): true")
	ufmt.Println("[EXPECTED] minted token should be the ibc/ wrapped voucher of base ugnot")
	ufmt.Println("[EXPECTED] receiver voucher balance should be 100 (full INITIALIZE amount minted)")
}

// buildPacketMembershipProof returns (storageRoot, encodedProof) for a single-leaf
// EVM-MPT proving that the packet's BatchPackets commitment path stores
// COMMITMENT_MAGIC. It mirrors storageProofFixture in the state-lens client's
// client_test.gno (the leaf encoding is the only laundering the verifier accepts).
func buildPacketMembershipProof(packet types.Packet) ([]byte, []byte) {
	batchHash := core.CommitPacketsHash([]types.Packet{packet})
	path := types.BatchPacketsPath(batchHash)

	slot, err := storage.IBCCommitmentKey(path[:])
	if err != nil {
		panic(err)
	}

	magic := types.COMMITMENT_MAGIC
	storedValue, err := storage.EncodeStorageValue(magic[:])
	if err != nil {
		panic(err)
	}

	storagePath, err := storage.StoragePath(slot[:])
	if err != nil {
		panic(err)
	}

	leaf := rlp.EncodeList(rlp.EncodeBytes(compactEncode(true, nibbles(storagePath[:]))), rlp.EncodeBytes(storedValue))
	root := keccak256.Sum256(leaf)

	proof := storage.EncodeProof(storage.Proof{
		Key:   slot[:],
		Value: magic[:],
		Proof: [][]byte{leaf},
	})

	return root[:], proof
}

// nibbles and compactEncode are copied verbatim from
// gno.land/p/onbloc/ibc/union/lightclient/state_lens/ics23_mpt/client_test.gno
// (they are test-only and unexported there). They produce the hex-prefix-encoded
// MPT leaf path that storage.VerifyProof expects.
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

// --- encoding helpers (pure z calls, mirroring the e2e harness) ---

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

// --- minimal L1 light client stub (state-lens needs an L1 client reference, but
// VerifyMembership reads only the stored consensus root and never consults it) ---

type mockL1Client struct{}

func (m *mockL1Client) VerifyMembership(uint64, []byte, []byte, []byte) error { return nil }
func (m *mockL1Client) VerifyNonMembership(uint64, []byte, []byte) error      { return nil }
func (m *mockL1Client) GetTimestamp() types.Timestamp                         { return types.Timestamp(1) }
func (m *mockL1Client) GetTimestampAtHeight(uint64) (types.Timestamp, error) {
	return types.Timestamp(1), nil
}
func (m *mockL1Client) GetLatestHeight() uint64        { return statelensProofHeight }
func (m *mockL1Client) GetCounterpartyChainID() string { return "l1" }
func (m *mockL1Client) Status() lightclient.Status     { return lightclient.Active }

func (m *mockL1Client) VerifyHeader(_ address, header []byte, _ address) (types.StateUpdate, error) {
	return types.StateUpdate{Height: statelensProofHeight}, nil
}

func (m *mockL1Client) VerifyCreation(address, address) (types.ClientCreationResult, error) {
	return types.ClientCreationResult{}, nil
}

func (m *mockL1Client) Misbehaviour(address, []byte, address) (types.ClientState, error) {
	return nil, errL1Unsupported
}

var errL1Unsupported = mockError("mock l1: unsupported")

type mockError string

func (e mockError) Error() string { return string(e) }

// Output:
// [SCENARIO] 1. Open a channel backed by the real state-lens/ics23-mpt light client
// [INFO] client opened: id=1 type=state-lens/ics23/mpt
// [INFO] channel opened (source=2 destination=1)
// [EXPECTED] client type should be state-lens/ics23/mpt (real, not mock)
// [EXPECTED] destination channel should be 1
//
// [SCENARIO] 2. Receive INITIALIZE order proven by the state-lens MPT proof (mint 100)
// [INFO] packet receipt recorded (state-lens MPT proof verified): true
// [INFO] minted token (wrapped voucher): ibc/e03a8753fa7f41c282b15cdc0343f660e6e65845
// [INFO] receiver voucher balance: 100
// [EXPECTED] packet receipt recorded (state-lens MPT proof verified): true
// [EXPECTED] minted token should be the ibc/ wrapped voucher of base ugnot
// [EXPECTED] receiver voucher balance should be 100 (full INITIALIZE amount minted)
