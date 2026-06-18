package impl

import (
	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/testutils/v0"
	z "gno.land/p/onbloc/ibc/union/zkgm"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
)

// helpers_test.gno holds test fixtures shared across the per-file test suites.
// Each *_test.gno file tests only the functions of its matching implementation
// file; the construction/encoding helpers used by several of them live here.

// newTestImpl builds a v1 impl bound to the proxy state singleton, the way the
// proxy injects it at Register time.
func newTestImpl() *ucs03ZkgmV1 {
	return &ucs03ZkgmV1{store: zkgm.Store()}
}

func testAddress(name string) string {
	return string(testutils.TestAddress(name))
}

// voucher read helpers: vouchers are proxy-owned state, so tests read them back
// through the store rather than a removed package-level getter.

func voucherBalanceOf(ibcDenom string, addr address) int64 {
	vou, ok := zkgm.Store().GetVoucher(ibcDenom)
	if !ok {
		return 0
	}
	return vou.Token().BalanceOf(addr)
}

func voucherNameOf(ibcDenom string) string {
	vou, ok := zkgm.Store().GetVoucher(ibcDenom)
	if !ok {
		return ""
	}
	return vou.Token().GetName()
}

func voucherSymbolOf(ibcDenom string) string {
	vou, ok := zkgm.Store().GetVoucher(ibcDenom)
	if !ok {
		return ""
	}
	return vou.Token().GetSymbol()
}

func voucherDecimalsOf(ibcDenom string) int {
	vou, ok := zkgm.Store().GetVoucher(ibcDenom)
	if !ok {
		return 0
	}
	return vou.Token().GetDecimals()
}

func mustZkgmPacketBytes(instr z.Instruction) []byte {
	out, err := z.EncodeZkgmPacket(z.ZkgmPacket{
		Salt:        [32]byte{},
		Path:        u256.Zero(),
		Instruction: instr,
	})
	if err != nil {
		panic(err)
	}
	return out
}

func mustCallBytes(call z.Call) []byte {
	out, err := z.EncodeCall(call)
	if err != nil {
		panic(err)
	}
	return out
}

func mustForwardBytes(forward z.Forward) []byte {
	out, err := z.EncodeForward(forward)
	if err != nil {
		panic(err)
	}
	return out
}

func batchMustCallInstruction(call z.Call) z.Instruction {
	return z.Instruction{Version: z.INSTR_VERSION_0, Opcode: z.OP_CALL, Operand: mustCallBytes(call)}
}

func batchMustOrderInstruction(order z.TokenOrderV2) z.Instruction {
	bz, err := z.EncodeTokenOrderV2(order)
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_2, Opcode: z.OP_TOKEN_ORDER, Operand: bz}
}

func batchMustBatchInstruction(batch z.Batch) z.Instruction {
	bz, err := z.EncodeBatch(batch)
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_0, Opcode: z.OP_BATCH, Operand: bz}
}
