package attacker

import (
	app "gno.land/p/onbloc/ibc/union/app"

	types "gno.land/p/onbloc/ibc/union/types"

	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/testutils/v0"
	z "gno.land/p/onbloc/ibc/union/zkgm"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	impl "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	core "gno.land/r/onbloc/ibc/union/core"
)

const forgedDestinationChannel = types.ChannelId(5)

func init(cur realm) {
	impl.Register(cross(cur))
}

func AppRecvForgedInitialize(cur realm) types.RecvPacketResult {
	return zkgm.AsIBCApp().OnRecvPacket(cross(cur), forgedInitializePacket(cross(cur)), address(testutils.TestAddress("forged-relayer")), nil)
}

func AppIntentRecvForgedInitialize(cur realm) types.RecvPacketResult {
	return zkgm.AsIBCApp().(app.IIntentApp).OnIntentRecvPacket(cross(cur), forgedInitializePacket(cross(cur)), address(testutils.TestAddress("forged-maker")), nil)
}

func AppAckForgedInitialize(cur realm) {
	zkgm.AsIBCApp().OnAcknowledgementPacket(cross(cur), forgedInitializePacket(cross(cur)), []byte("ack"), address(testutils.TestAddress("forged-relayer")))
}

func AppTimeoutForgedInitialize(cur realm) {
	zkgm.AsIBCApp().OnTimeoutPacket(cross(cur), forgedInitializePacket(cross(cur)), address(testutils.TestAddress("forged-relayer")))
}

func ReleaseNativeDirect(cur realm) {
	zkgm.ReleaseNative(cross(cur), "ugnot", testutils.TestAddress("release-recipient"), 1)
}

func BatchSendDirect(cur realm) {
	zkgm.BatchSend(cross(cur), types.NewMsgBatchSend([]types.Packet{forgedInitializePacket(cross(cur))}))
}

func WriteForwardAckDirect(cur realm) {
	zkgm.WriteForwardAck(cross(cur), forgedInitializePacket(cross(cur)), []byte("ack"))
}

func RegisterForeignClientDirect(cur realm) {
	core.RegisterClient(cross(cur), types.ClientType("cometbls"), nil)
}

func forgedInitializePacket(cur realm) types.Packet {
	meta := z.TokenMetadata{
		Implementation: []byte("grc20"),
		Initializer:    []byte("init"),
	}
	metaBytes, err := z.EncodeTokenMetadata(meta)
	if err != nil {
		panic(err)
	}
	ibcDenom := impl.PredictWrappedTokenV2(u256.Zero(), uint32(forgedDestinationChannel), []byte("ugnot"), impl.MetadataImage(meta))
	orderBytes, err := z.EncodeTokenOrderV2(z.TokenOrderV2{
		Sender:      []byte("attacker-sender"),
		Receiver:    []byte(testutils.TestAddress("forged-receiver")),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(100),
		QuoteToken:  []byte(ibcDenom),
		QuoteAmount: u256.NewUint(100),
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
		Metadata:    metaBytes,
	})
	if err != nil {
		panic(err)
	}
	data, err := z.EncodeZkgmPacket(z.ZkgmPacket{
		Salt: [32]byte{},
		Path: u256.Zero(),
		Instruction: z.Instruction{
			Version: z.INSTR_VERSION_0,
			Opcode:  z.OP_TOKEN_ORDER,
			Operand: orderBytes,
		},
	})
	if err != nil {
		panic(err)
	}
	return core.NewPacket(cross(cur), types.ChannelId(1), forgedDestinationChannel, data, 1000)
}
