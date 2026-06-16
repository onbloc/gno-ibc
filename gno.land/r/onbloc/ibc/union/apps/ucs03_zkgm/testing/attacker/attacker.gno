package attacker

import (
	z "gno.land/p/onbloc/ibc/union/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/testutils/v0"
	core "gno.land/r/onbloc/ibc/union/core"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	_ "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/loader"
	impl "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
)

const forgedDestinationChannel = core.ChannelId(5)

func AppRecvForgedInitialize(cur realm) core.RecvPacketResult {
	return zkgm.AsIBCApp().OnRecvPacket(cross(cur), forgedInitializePacket(cross(cur)), address(testutils.TestAddress("forged-relayer")), nil)
}

func AppIntentRecvForgedInitialize(cur realm) core.RecvPacketResult {
	return zkgm.AsIBCApp().(core.IIntentApp).OnIntentRecvPacket(cross(cur), forgedInitializePacket(cross(cur)), address(testutils.TestAddress("forged-maker")), nil)
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
	zkgm.BatchSend(cross(cur), core.NewMsgBatchSend(cross(cur), []core.Packet{forgedInitializePacket(cross(cur))}))
}

func WriteForwardAckDirect(cur realm) {
	zkgm.WriteForwardAck(cross(cur), forgedInitializePacket(cross(cur)), []byte("ack"))
}

func RegisterForeignClientDirect(cur realm) {
	core.RegisterClient(cross(cur), core.ClientType("cometbls"), nil)
}

func forgedInitializePacket(cur realm) core.Packet {
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
	return core.NewPacket(cross(cur), core.ChannelId(1), forgedDestinationChannel, data, 0, 1000)
}
