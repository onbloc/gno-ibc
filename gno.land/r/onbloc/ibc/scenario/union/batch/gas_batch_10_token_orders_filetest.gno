// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/batch
package batch

// measures gas usage for 1 batch with 10 TokenOrders

import (
	"chain"
	"testing"

	"gno.land/p/onbloc/ibc/union/types"
	z "gno.land/p/onbloc/ibc/union/zkgm"

	u256 "gno.land/p/gnoswap/uint256"

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

	adminAddr    = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
	receiverAddr = address("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm")
)

func main(cur realm) {
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

	meta := mustTokenMetadata("grc20", z.TokenInitializer{Name: "Gno Token", Symbol: "GNOT", Decimals: 6})
	quoteToken := z.PredictWrappedTokenV2(u256.Zero(), uint32(channelId), []byte("ugnot"), z.MetadataImage(mustDecodeMeta(meta)))

	// Build batch with 10 TokenOrders
	var instructions []z.Instruction
	for i := 0; i < 10; i++ {
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
		instr := mustOrderInstruction(order)
		instructions = append(instructions, instr)
	}

	batch := z.Batch{Instructions: instructions}
	batchInstr := mustBatchInstruction(batch)
	packet := core.NewPacket(types.ChannelId(2), channelId, mustPacketData(batchInstr), types.Timestamp(1<<62))

	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{packet}, [][]byte{nil}, nil, 1))

	println("[RESULT] Batch with 10 TokenOrders sent successfully")
}

// --- encoding helpers ---

func mustOrderInstruction(order z.TokenOrderV2) z.Instruction {
	operand, err := z.EncodeTokenOrderV2(order)
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_2, Opcode: z.OP_TOKEN_ORDER, Operand: operand}
}

func mustBatchInstruction(b z.Batch) z.Instruction {
	operand, err := z.EncodeBatch(b)
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_0, Opcode: z.OP_BATCH, Operand: operand}
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

// Gas:
// 91264946

// Output:
// [RESULT] Batch with 10 TokenOrders sent successfully
