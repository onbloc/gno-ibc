// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/send
package send

// token_send_voucher_escrow_protocol_fill_ack_by_statelens_real_cometbls_filetest funds a sender, escrows (locks)
// a ucs03-zkgm voucher, then acknowledges the sent packet with an
// acknowledgement proven by the real state-lens/ics23-mpt light client whose L1
// is a REAL cometbls light client (not a mock).
//
// The acknowledgement's L2 consensus is added to the state-lens client via
// UpdateClient, which drives VerifyHeader -> l1.VerifyMembership: the real
// cometbls L1 verifies an inline 2-level ICS23 proof that the L2 consensus is
// committed under its consensus root. The ack receipt only exists after Send,
// so the L1's consensus root (which must commit it) is installed after Send via
// an admin ForceUpdateClient — the verification itself is genuine, only the
// scenario-controlled root is seeded rather than anchored to a devnet chain.

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

	adminAddr  = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
	senderAddr = address("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm")

	l2ClientID = uint32(7)

	fundHeight = uint64(100) // state-lens L2 height of the funding consensus
	ackHeight  = uint64(200) // state-lens L2 height of the ack consensus
	l1Height   = uint64(500) // cometbls L1 height committing the ack consensus
)

func main(cur realm) {
	fx := buildSendFixture()

	println("[SCENARIO] 1. Open a state-lens channel whose L1 is a REAL cometbls client and fund the sender")
	clientId, l1ClientId := openAndFundSender(cur, fx.l1Contract, fx.fundRoot, fx.initPacket, fx.fundProof, fx.counterpartyChannel, fx.quoteToken)
	println("")

	println("[SCENARIO] 2. Send ESCROW order locking 40 of the voucher")
	sendPacket := sendEscrowOrder(cur, fx.channelId, fx.quoteToken)
	println("")

	println("[SCENARIO] 3. Acknowledge via state-lens, with the ack L2 consensus proven by the real cometbls L1")
	acknowledgeWithCometblsProof(cur, fx.l1Contract, l1ClientId, clientId, sendPacket, fx.quoteToken)
}

// sendFixture holds the deterministic funding packet, its proof, and the storage
// root the scenario builds up front and threads through its steps.
type sendFixture struct {
	channelId           types.ChannelId
	counterpartyChannel types.ChannelId
	l1Contract          types.H256
	fundRoot            []byte
	initPacket          types.Packet
	fundProof           []byte
	quoteToken          string
}

// buildSendFixture builds the deterministic funding packet and the single-leaf
// EVM-MPT proof + storage root that commits it. The first channel opened is
// ChannelId(1) and a zero L1 contract address is used for the proof and the seeded
// client (they match), so the wrapped denom and the packet are known up front.
func buildSendFixture() sendFixture {
	channelId := types.ChannelId(1)
	counterpartyChannel := types.ChannelId(2)
	var l1Contract types.H256
	meta := tokenMetadata("grc20", z.TokenInitializer{Name: "Gno Token", Symbol: "GNOT", Decimals: 6})
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
	initPacket := core.NewPacket(counterpartyChannel, channelId, packetData(orderInstruction(initOrder)), types.Timestamp(1<<62))
	// The funding consensus is seeded directly at state-lens creation, so the recv
	// does not exercise the L1 (it only checks the L1 is Active via Status).
	fundRoot, fundProof := buildMembershipProof(types.BatchPacketsPath(core.CommitPacketsHash([]types.Packet{initPacket})), commitmentMagic())

	return sendFixture{
		channelId:           channelId,
		counterpartyChannel: counterpartyChannel,
		l1Contract:          l1Contract,
		fundRoot:            fundRoot,
		initPacket:          initPacket,
		fundProof:           fundProof,
		quoteToken:          quoteToken,
	}
}

// openAndFundSender creates the real cometbls L1 client (placeholder root, id 1)
// and the state-lens L2 client (funding consensus, id 2), Force-opens the
// connection/channel, and receives the proven funding packet. It returns the
// state-lens client id and the L1 client id.
//
// It is kept inline (not split further): every admin/relayer core entrypoint
// authorizes the caller via cur.Previous(), so testing.SetRealm and the cross(cur)
// call must run in the same frame for the admin user to be seen as the caller.
func openAndFundSender(cur realm, l1Contract types.H256, fundRoot []byte, initPacket types.Packet, fundProof []byte, counterpartyChannel types.ChannelId, quoteToken string) (types.ClientId, types.ClientId) {
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.UpdateImpl(cross(cur), coreImplPath)
	zkgm.UpdateImpl(cross(cur), zkgmImplPath)
	zkgm.SetRateLimitDisabled(cross(cur), true)
	zkgm.RegisterCoreApp(cross(cur))
	access.GrantRole(cross(cur), access.RelayerRole, adminAddr)

	// Create the real cometbls L1 client (id 1) with a placeholder root: it only
	// needs to be Active until the ack, when it is re-seeded to commit the ack
	// consensus (the ack receipt is not known until after Send).
	placeholderRoot := make([]byte, 32)
	l1CSBytes, l1ConsBytes := scenariocometbls.SeededClientBytes(l1Contract, l1Height, placeholderRoot)
	l1ClientType := types.ClientType(scenariocometbls.ClientType)
	core.RegisterClient(cross(cur), l1ClientType, scenariocometbls.NewLightClient)
	core.CreateClient(cross(cur), core.NewMsgCreateClient(l1ClientType, l1CSBytes, l1ConsBytes))
	l1ClientId := types.ClientId(1)

	// Create the state-lens L2 client (id 2) with the funding consensus.
	clientState := &ics23mpt.ClientState{
		L2ChainID:         "l2-chain",
		L1ClientID:        1,
		L2ClientID:        l2ClientID,
		L2LatestHeight:    fundHeight,
		TimestampOffset:   64,
		StateRootOffset:   0,
		StorageRootOffset: 32,
	}
	fundConsensus := &ics23mpt.ConsensusState{Timestamp: 1, StateRoot: make([]byte, 32), StorageRoot: fundRoot}
	stateLensType := types.ClientType(ics23mpt.ClientType)
	core.RegisterClient(cross(cur), stateLensType, newStateLensClient)
	core.CreateClient(cross(cur), core.NewMsgCreateClient(stateLensType, fixture.Must(ics23mpt.EncodeClientState(*clientState)), fixture.Must(ics23mpt.EncodeConsensusState(*fundConsensus))))
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

	return clientId, l1ClientId
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
	sendPacket := zkgm.Send(cross(cur), channelId, types.Timestamp(1<<62), [32]byte{}, orderInstruction(order))

	ufmt.Printf("[INFO] sender voucher balance after send: %d\n", zkgm.VoucherBalanceOf(quoteToken, senderAddr))
	ufmt.Printf("[INFO] proxy escrow balance after send: %d\n", zkgm.VoucherBalanceOf(quoteToken, zkgm.ProxyAddress()))
	ufmt.Println("[EXPECTED] sender voucher balance after send should be 60 (100 - 40 escrowed)")
	ufmt.Println("[EXPECTED] proxy escrow balance after send should be 40 (locked)")

	return sendPacket
}

// acknowledgeWithCometblsProof builds the ack L2 consensus and the inline L1
// membership proof committing it, re-seeds the L1 so its consensus root matches
// (ForceUpdateClient), adds the L2 consensus via UpdateClient (driving the genuine
// cometbls VerifyMembership), then acknowledges the sent packet. The protocol-fill
// ack is a no-op for an escrow, so the lock holds.
func acknowledgeWithCometblsProof(cur realm, l1Contract types.H256, l1ClientId, clientId types.ClientId, sendPacket types.Packet, quoteToken string) {
	ack := fixture.SuccessAck(fixture.ProtocolFillAck())
	ackCommitment := types.CommitAcks([][]byte{ack})
	ackRoot, ackProof := buildMembershipProof(types.BatchReceiptsPath(core.CommitPacketsHash([]types.Packet{sendPacket})), ackCommitment[:])

	// The ack receipt is now known: build the ack L2 consensus and the inline L1
	// membership proof committing it, then re-seed the L1 so its consensus root
	// matches and the genuine cometbls VerifyMembership accepts the proof.
	l2AckConsensus := makeConsensusBytes(2, make([]byte, 32), ackRoot)
	l1Proof, l1Root := scenariocometbls.ProveConsensus(l1Contract, types.ClientId(l2ClientID), ackHeight, l2AckConsensus)
	reseedCSBytes, reseedConsBytes := scenariocometbls.SeededClientBytes(l1Contract, l1Height, l1Root)

	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.ForceUpdateClient(cross(cur), types.NewMsgForceUpdateClient(l1ClientId, reseedCSBytes, reseedConsBytes))

	header := ics23mpt.Header{
		L1Height:              l1Height,
		L2Height:              ackHeight,
		L2ConsensusStateProof: l1Proof,
		L2ConsensusState:      l2AckConsensus,
	}
	core.UpdateClient(cross(cur), types.NewMsgUpdateClient(clientId, fixture.Must(ics23mpt.EncodeHeader(header))))

	core.PacketAcknowledgement(cross(cur), core.NewMsgPacketAcknowledgement([]types.Packet{sendPacket}, [][]byte{ack}, ackProof, ackHeight))

	ufmt.Printf("[INFO] sender voucher balance after ack: %d\n", zkgm.VoucherBalanceOf(quoteToken, senderAddr))
	ufmt.Printf("[INFO] proxy escrow balance after ack: %d\n", zkgm.VoucherBalanceOf(quoteToken, zkgm.ProxyAddress()))
	ufmt.Println("[EXPECTED] sender voucher balance after ack should be 60 (unchanged: escrow stays locked)")
	ufmt.Println("[EXPECTED] proxy escrow balance after ack should be 40 (unchanged: escrow stays locked)")
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

func commitmentMagic() []byte {
	magic := types.COMMITMENT_MAGIC
	return magic[:]
}

// --- inline proof + encoding helpers (filetests are self-contained) ---

// buildMembershipProof returns (storageRoot, encodedProof) for a single-leaf
// EVM-MPT proving that commitmentPath stores value.
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
// [SCENARIO] 1. Open a state-lens channel whose L1 is a REAL cometbls client and fund the sender
// [INFO] sender voucher balance after fund: 100
// [EXPECTED] sender voucher balance after fund should be 100
//
// [SCENARIO] 2. Send ESCROW order locking 40 of the voucher
// [INFO] sender voucher balance after send: 60
// [INFO] proxy escrow balance after send: 40
// [EXPECTED] sender voucher balance after send should be 60 (100 - 40 escrowed)
// [EXPECTED] proxy escrow balance after send should be 40 (locked)
//
// [SCENARIO] 3. Acknowledge via state-lens, with the ack L2 consensus proven by the real cometbls L1
// [INFO] sender voucher balance after ack: 60
// [INFO] proxy escrow balance after ack: 40
// [EXPECTED] sender voucher balance after ack should be 60 (unchanged: escrow stays locked)
// [EXPECTED] proxy escrow balance after ack should be 40 (unchanged: escrow stays locked)
