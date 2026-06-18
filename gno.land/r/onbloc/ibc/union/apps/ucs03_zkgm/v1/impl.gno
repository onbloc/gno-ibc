package impl

import (
	types "gno.land/p/onbloc/ibc/union/types"

	u256 "gno.land/p/gnoswap/uint256"
	z "gno.land/p/onbloc/ibc/union/zkgm"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
)

type ZkgmV1 struct{}

// New constructs a fresh v1 impl.
// Before the proxy has an installed impl, any bootstrap loader may construct it.
// After bootstrap, only the production impl realm may construct it again.
func New(cur realm) zkgm.ZkgmImpl {
	caller := cur.Previous().PkgPath()
	if caller != zkgm.ProductionImplPath() && zkgm.Bootstrapped() {
		panic("not allowed")
	}
	return &ZkgmV1{}
}

func Register(cur realm) {
	if zkgm.Bootstrapped() {
		panic("zkgm: already bootstrapped")
	}
	zkgm.UpdateImpl(cross(cur), zkgm.NewUpdateRequest(cross(cur), New(cur), []string{}))
	zkgm.RegisterCoreApp(cross(cur))
}

func (v *ZkgmV1) PreChannelOpenInit(cur realm, channelId types.ChannelId) {}

func (v *ZkgmV1) PreChannelOpenTry(cur realm, channelId types.ChannelId, counterpartyVersion string) {
}

func (v *ZkgmV1) PostChannelOpenAck(cur realm, channelId types.ChannelId, counterpartyChannelId types.ChannelId) {
}

func (v *ZkgmV1) PostChannelOpenConfirm(cur realm, channelId types.ChannelId) {}

func (v *ZkgmV1) PreChannelCloseInit(cur realm, channelId types.ChannelId) {}

func (v *ZkgmV1) PostChannelCloseConfirm(cur realm, channelId types.ChannelId) {}

func (v *ZkgmV1) Recv(cur realm, packet types.Packet, relayer address, relayerMsg []byte) types.RecvPacketResult {
	zp, err := z.DecodeZkgmPacket(cloneBytes(packet.Data))
	if err != nil {
		zkgm.EmitRecvError(packet.SourceChannelId, packet.DestinationChannelId, err.Error())
		return failureResult(cur, universalErrorAck())
	}
	res, err := v.dispatchExecute(cur, packet, relayer, relayerMsg, zp.Path, zp.Salt, zp.Instruction, false)
	if err != nil {
		zkgm.EmitRecvError(packet.SourceChannelId, packet.DestinationChannelId, err.Error())
		return failureResult(cur, universalErrorAck())
	}
	return res
}

func (v *ZkgmV1) Ack(cur realm, packet types.Packet, ack []byte, relayer address) {
	zp, err := z.DecodeZkgmPacket(cloneBytes(packet.Data))
	if err != nil {
		panic(err.Error())
	}
	if v.handleForwardChild(cur, packet, zp, ack) {
		return
	}

	if err := v.dispatchAck(cur, packet, zp.Path, zp.Salt, zp.Instruction, ack); err != nil {
		panic(err.Error())
	}
}

func (v *ZkgmV1) Timeout(cur realm, packet types.Packet, relayer address) {
	zp, err := z.DecodeZkgmPacket(cloneBytes(packet.Data))
	if err != nil {
		panic(err.Error())
	}
	if v.handleForwardChild(cur, packet, zp, universalErrorAck()) {
		return
	}

	if err := v.dispatchTimeout(cur, packet, zp.Path, zp.Salt, zp.Instruction); err != nil {
		panic(err.Error())
	}
}

// IntentRecv executes the market-maker fast path.
// Only-maker outcomes revert the intent tx so proven recv can proceed.
func (v *ZkgmV1) IntentRecv(cur realm, packet types.Packet, marketMaker address, marketMakerMsg []byte) types.RecvPacketResult {
	zp, err := z.DecodeZkgmPacket(cloneBytes(packet.Data))
	if err != nil {
		zkgm.EmitRecvError(packet.SourceChannelId, packet.DestinationChannelId, err.Error())
		return failureResult(cur, universalErrorAck())
	}
	res, err := v.dispatchExecute(cur, packet, marketMaker, marketMakerMsg, zp.Path, zp.Salt, zp.Instruction, true)
	if err != nil {
		zkgm.EmitRecvError(packet.SourceChannelId, packet.DestinationChannelId, err.Error())
		return failureResult(cur, universalErrorAck())
	}
	// Only-maker must roll back the intent receipt.
	if isOnlyMakerAck(res.Acknowledgement) {
		panic("zkgm: only maker")
	}
	return res
}

func (v *ZkgmV1) Send(cur realm, req zkgm.SendRequest) ([]byte, error) {
	// dispatchVerify uses the raw user salt; only the wire packet is namespaced.
	budget := newSentCoinBudget(parseCoins(req.SentCoins))
	if err := v.dispatchVerify(cur, req.ChannelId, req.Sender, budget, u256.Zero(), req.Salt, req.Instruction); err != nil {
		return nil, err
	}
	if err := budget.assertDrained(); err != nil {
		return nil, err
	}

	// Only user-initiated sends apply DeriveSenderSalt. Forwarded packets are
	// built in forward.gno and use DeriveForwardSalt instead.
	hashedSalt := z.DeriveSenderSalt([]byte(req.Sender), req.Salt)
	data, err := z.EncodeZkgmPacket(z.ZkgmPacket{
		Salt:        hashedSalt,
		Path:        u256.Zero(),
		Instruction: req.Instruction,
	})
	if err != nil {
		return nil, err
	}

	return data, nil
}

func (v *ZkgmV1) Render(pkgpath string, path string) string {
	if path == "" {
		return "zkgm v1"
	}
	return "zkgm/v1: render path not found: " + path
}

var _ zkgm.ZkgmImpl = &ZkgmV1{}
