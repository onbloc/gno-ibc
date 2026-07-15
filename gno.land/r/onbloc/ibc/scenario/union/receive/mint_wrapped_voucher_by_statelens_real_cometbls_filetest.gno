// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/receive
package receive

// mint_wrapped_voucher_by_statelens_real_cometbls_filetest receives a ucs03-zkgm token
// packet proven by the real state-lens/ics23-mpt light client whose L1 is a REAL
// cometbls light client (not a mock).
//
// Unlike mint_wrapped_voucher_by_statelens_filetest — which seeds the L2 consensus at
// client creation and stubs the L1 with a mockL1Client — this scenario adds the
// L2 consensus via UpdateClient. That drives the state-lens VerifyHeader path,
// which asks the L1 cometbls client to prove the L2 consensus state is committed
// in the L1 state: l1.VerifyMembership(L1Height, consensusPath, proof,
// keccak(L2Consensus)). The proof is an inline 2-level (iavl -> tendermint)
// ICS23 membership proof built by the scenario cometbls L1 harness, and the
// cometbls consensus root is seeded to exactly what that proof commits to — so
// the genuine cometbls verification path runs and accepts it.

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
	fixture "gno.land/p/onbloc/ibc/testing/zkgm/fixture"
	z "gno.land/p/onbloc/ibc/union/zkgm"

	scenariocometbls "gno.land/r/onbloc/ibc/scenario/helper/cometbls"
	"gno.land/r/onbloc/ibc/union/access"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	_ "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1" // install zkgm v1 impl (init registers the constructor)
	core "gno.land/r/onbloc/ibc/union/core"
	_ "gno.land/r/onbloc/ibc/union/core/v1"
)

const (
	coreImplPath = "gno.land/r/onbloc/ibc/union/core/v1"
	zkgmImplPath = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"

	adminAddr    = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
	receiverAddr = address("g1dyxy88p94acjnm8dmu9tfj2mv2ncvx83cagllu")

	// l2ClientID is the L2 client id on the L1 chain (the state-lens
	// ClientState.L2ClientID), whose consensus path the L1 proof commits.
	l2ClientID = uint32(7)

	// l1Height is the cometbls L1 height whose seeded consensus root commits the
	// L2 consensus; l2ProofHeight is the L2 height the consensus is stored at and
	// the height the packet is proven against.
	l1Height      = uint64(500)
	genesisHeight = uint64(1)
	l2ProofHeight = uint64(100)
)

func main(cur realm) {
	fx := buildRecvFixture()

	println("[SCENARIO] 1. Open a state-lens channel whose L1 is a REAL cometbls client")
	clientId := openCometblsStateLensChannel(cur, fx.l1Contract, fx.l1Root, fx.sourceChannel)
	println("")

	println("[SCENARIO] 2. UpdateClient: add the L2 consensus, proven by the real cometbls L1")
	updateL2Consensus(cur, clientId, fx.l1Proof, fx.l2Consensus)
	println("")

	println("[SCENARIO] 3. Receive INITIALIZE order proven by the state-lens MPT proof (mint 100)")
	receiveProvenOrder(cur, fx.packet, fx.packetProof, fx.quoteToken)
}

// recvFixture holds the deterministic packet, proofs, and consensus blobs the
// scenario builds up front and threads through its steps.
type recvFixture struct {
	sourceChannel types.ChannelId
	l1Contract    types.H256
	l1Root        []byte
	l1Proof       []byte
	l2Consensus   []byte
	packet        types.Packet
	packetProof   []byte
	quoteToken    string
}

// buildRecvFixture builds the deterministic recv packet, its inline EVM-MPT proof,
// and the L1 membership proof + cometbls root committing the L2 consensus. The
// first channel opened is ChannelId(1) and a zero L1 contract address is used for
// the proof and the seeded client (they match), so everything is known up front.
func buildRecvFixture() recvFixture {
	channelId := types.ChannelId(1)
	sourceChannel := types.ChannelId(2)
	meta := tokenMetadata("\xaf\x73\x9f\x34\xdd\xf9\x51\xcb\xc2\x4f\xdb\xba\x4f\x76\x21\x36\x88\xe1\x36\x27", z.TokenInitializer{Name: "Gno Token", Symbol: "GNOT", Decimals: 6})
	quoteToken := z.PredictWrappedTokenV2(u256.Zero(), uint32(channelId), []byte("ugnot"), z.MetadataImage(mustDecodeMeta(meta)))
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
	packet := core.NewPacket(sourceChannel, channelId, packetData(orderInstruction(order)), types.Timestamp(1<<62))

	// storageRoot commits the recv packet; l2Consensus stores it at the client
	// offsets (state_root@0, storage_root@32, timestamp@64).
	storageRoot, packetProof := buildPacketMembershipProof(packet)
	l2Consensus := makeConsensusBytes(1, make([]byte, 32), storageRoot)

	var l1Contract types.H256
	l1Proof, l1Root := scenariocometbls.ProveConsensus(l1Contract, types.ClientId(l2ClientID), l2ProofHeight, l2Consensus)

	return recvFixture{
		sourceChannel: sourceChannel,
		l1Contract:    l1Contract,
		l1Root:        l1Root,
		l1Proof:       l1Proof,
		l2Consensus:   l2Consensus,
		packet:        packet,
		packetProof:   packetProof,
		quoteToken:    quoteToken,
	}
}

// openCometblsStateLensChannel creates the real cometbls L1 client (seeded with
// l1Root), creates the state-lens L2 client with a genesis-only consensus, and
// Force-opens the connection/channel. It returns the state-lens client id.
//
// It is kept inline (not split further): every admin/relayer core entrypoint
// authorizes the caller via cur.Previous(), so testing.SetRealm and the cross(cur)
// call must run in the same frame for the admin user to be seen as the caller.
func openCometblsStateLensChannel(cur realm, l1Contract types.H256, l1Root []byte, sourceChannel types.ChannelId) types.ClientId {
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.UpdateImpl(cross(cur), coreImplPath)
	zkgm.UpdateImpl(cross(cur), zkgmImplPath)
	zkgm.SetRateLimitDisabled(cross(cur), true)
	zkgm.RegisterCoreApp(cross(cur))
	access.GrantRole(cross(cur), access.RelayerRole, adminAddr)

	// Create the real cometbls L1 client (id 1) seeded with that root. The
	// register/create calls are made here (as the relayer-authorized admin),
	// not inside the helper realm, so the access check sees the right caller.
	l1ClientStateBytes, l1ConsensusStateBytes := scenariocometbls.SeededClientBytes(l1Contract, l1Height, l1Root)
	l1ClientType := types.ClientType(scenariocometbls.ClientType)
	core.RegisterClient(cross(cur), l1ClientType, scenariocometbls.NewLightClient)
	core.CreateClient(cross(cur), core.NewMsgCreateClient(l1ClientType, l1ClientStateBytes, l1ConsensusStateBytes))
	ufmt.Println("[INFO] real cometbls L1 client created (id 1)")

	// Create the state-lens L2 client (id 2) with a genesis consensus only; the
	// packet-height consensus is added later via UpdateClient through the L1.
	clientState := &ics23mpt.ClientState{
		L2ChainID:         "l2-chain",
		L1ClientID:        1,
		L2ClientID:        l2ClientID,
		L2LatestHeight:    genesisHeight,
		TimestampOffset:   64,
		StateRootOffset:   0,
		StorageRootOffset: 32,
	}
	genesisConsensus := &ics23mpt.ConsensusState{Timestamp: 1, StateRoot: make([]byte, 32), StorageRoot: make([]byte, 32)}
	clientStateBytes := fixture.Must(ics23mpt.EncodeClientState(*clientState))
	consensusStateBytes := fixture.Must(ics23mpt.EncodeConsensusState(*genesisConsensus))

	clientType := types.ClientType(ics23mpt.ClientType)
	core.RegisterClient(cross(cur), clientType, newStateLensClient)
	core.CreateClient(cross(cur), core.NewMsgCreateClient(clientType, clientStateBytes, consensusStateBytes))
	clientId := types.ClientId(2)

	// Force-open connection + channel (admin variants skip the handshake proofs).
	core.ConnectionOpenInit(cross(cur), core.NewMsgConnectionOpenInit(clientId, types.ClientId(99)))
	connectionId := types.ConnectionId(1)
	core.ForceConnectionOpenAck(cross(cur), core.NewMsgConnectionOpenAck(connectionId, types.ConnectionId(77), nil, 0))

	portId := []byte(zkgm.ProxyPkgPath())
	core.ChannelOpenInit(cross(cur), core.NewMsgChannelOpenInit(portId, portId, connectionId, zkgm.Version, "g1relayer"))
	opened := types.ChannelId(1)
	core.ForceChannelOpenAck(cross(cur), core.NewMsgChannelOpenAck(opened, zkgm.Version, sourceChannel, nil, 0, "g1relayer"))
	ufmt.Printf("[INFO] state-lens channel opened (source=%s destination=%s)\n", sourceChannel.String(), opened.String())

	return clientId
}

// updateL2Consensus adds the L2 consensus at l2ProofHeight via UpdateClient, which
// drives VerifyHeader -> the real cometbls L1's VerifyMembership on l1Proof.
func updateL2Consensus(cur realm, clientId types.ClientId, l1Proof, l2Consensus []byte) {
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	header := ics23mpt.Header{
		L1Height:              l1Height,
		L2Height:              l2ProofHeight,
		L2ConsensusStateProof: l1Proof,
		L2ConsensusState:      l2Consensus,
	}
	core.UpdateClient(cross(cur), types.NewMsgUpdateClient(clientId, fixture.Must(ics23mpt.EncodeHeader(header))))
	latest, _ := core.GetLatestHeight(clientId)
	ufmt.Printf("[INFO] state-lens latest height after L1-proven update: %d\n", latest)
	ufmt.Println("[EXPECTED] state-lens latest height should be 100 (L2 consensus added via the real L1)")
}

// receiveProvenOrder receives the packet proven by the freshly-added consensus and
// asserts the receipt is recorded and the wrapped voucher is minted.
func receiveProvenOrder(cur realm, packet types.Packet, packetProof []byte, quoteToken string) {
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{packet}, [][]byte{nil}, packetProof, l2ProofHeight))

	_, receiptErr := core.GetBatchReceipts(core.CommitPacketsHash([]types.Packet{packet}))
	ufmt.Printf("[INFO] packet receipt recorded: %t\n", receiptErr == nil)
	ufmt.Printf("[INFO] receiver voucher balance: %d\n", zkgm.VoucherBalanceOf(quoteToken, receiverAddr))
	ufmt.Println("[EXPECTED] packet receipt recorded: true")
	ufmt.Println("[EXPECTED] receiver voucher balance should be 100 (full INITIALIZE amount minted)")
}

func newStateLensClient(csBytes, consBytes []byte) (lightclient.Interface, error) {
	cs, err := ics23mpt.DecodeClientState(csBytes)
	if err != nil {
		return nil, err
	}
	cons, err := ics23mpt.DecodeConsensusState(consBytes)
	if err != nil {
		return nil, err
	}

	return ics23mpt.NewStateLensIcs23MptLightClient(&cs, &cons, core.GetLightClient)
}

// --- inline proof + encoding helpers (filetests are self-contained) ---

// buildPacketMembershipProof returns (storageRoot, encodedProof) for a
// single-leaf EVM-MPT proving the packet's BatchPackets commitment path stores
// COMMITMENT_MAGIC. Mirrors mint_wrapped_voucher_by_statelens_filetest.
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

	proof := storage.EncodeProof(storage.Proof{Key: slot[:], Value: magic[:], Proof: [][]byte{leaf}})

	return root[:], proof
}

// makeConsensusBytes lays out an L2 consensus blob matching the client offsets
// (state_root@0, storage_root@32, big-endian timestamp@64).
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

// orderInstruction / packetData wrap the fixture toolkit for this scenario's
// fixed shape: a v2 TokenOrder top-level instruction in a zero-salt, path-0
// packet.
func orderInstruction(order z.TokenOrderV2) z.Instruction {
	return fixture.Instruction(z.INSTR_VERSION_2, z.OP_TOKEN_ORDER, fixture.Must(z.EncodeTokenOrderV2(order)))
}

func packetData(instr z.Instruction) []byte {
	return fixture.EncodePacket(fixture.Packet([32]byte{}, 0, instr))
}

func tokenMetadata(implementation string, ti z.TokenInitializer) []byte {
	initBytes := fixture.Must(z.EncodeTokenInitializer(ti))

	return fixture.Must(z.EncodeTokenMetadata(z.TokenMetadata{Implementation: []byte(implementation), Initializer: initBytes}))
}

func mustDecodeMeta(bz []byte) z.TokenMetadata {
	meta, err := z.DecodeTokenMetadata(bz)
	if err != nil {
		panic(err)
	}

	return meta
}

// Output:
// [SCENARIO] 1. Open a state-lens channel whose L1 is a REAL cometbls client
// [INFO] real cometbls L1 client created (id 1)
// [INFO] state-lens channel opened (source=2 destination=1)
//
// [SCENARIO] 2. UpdateClient: add the L2 consensus, proven by the real cometbls L1
// [INFO] state-lens latest height after L1-proven update: 100
// [EXPECTED] state-lens latest height should be 100 (L2 consensus added via the real L1)
//
// [SCENARIO] 3. Receive INITIALIZE order proven by the state-lens MPT proof (mint 100)
// [INFO] packet receipt recorded: true
// [INFO] receiver voucher balance: 100
// [EXPECTED] packet receipt recorded: true
// [EXPECTED] receiver voucher balance should be 100 (full INITIALIZE amount minted)
