package ucs03_zkgm

import (
	"encoding/hex"
	"time"

	types "gno.land/p/onbloc/ibc/union/types"

	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/testutils/v0"
	z "gno.land/p/onbloc/ibc/union/zkgm"
)

const (
	zkgmProxyRealmPath = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
)

// zkgmERC20ImplHex is the ZkgmERC20 implementation contract address (Sepolia
// deploy) carried as TokenMetadata.Implementation for EVM-destined wrapped
// tokens; see gno.land/p/onbloc/ibc/union/zkgm/abi.gno's tokenInitializerSelector doc.
const zkgmERC20ImplHex = "af739f34ddf951cbc24fdbba4f76213688e13627"

func mustHexBytes(s string) []byte {
	bz, err := hex.DecodeString(s)
	if err != nil {
		panic(err)
	}
	return bz
}

var zkgmERC20Impl = mustHexBytes(zkgmERC20ImplHex)

// Crossing test shims for the send-side verify path. The production verify
// methods take the borrow form (0, rlm) and read the sender from
// rlm.Previous().Address() (MessageInfo was removed). A direct non-crossing test
// call leaves rlm.Previous() empty, so these crossing wrappers let
// testing.SetRealm(testing.NewUserRealm(sender)) + cross(cur) drive the sender
// the verify path observes, exactly as the proxy Send entry does in production.
func (v *ucs03ZkgmV1) verifyTokenOrderV2X(cur realm, funds *funds, channelId types.ChannelId, path *u256.Uint, order z.TokenOrderV2) error {
	return v.verifyTokenOrderV2(0, cur, funds, channelId, path, order)
}

func (v *ucs03ZkgmV1) verifyInternalX(cur realm, funds *funds, channelId types.ChannelId, path *u256.Uint, instruction z.Instruction) error {
	return v.verifyInternal(0, cur, funds, channelId, path, instruction)
}

func (v *ucs03ZkgmV1) verifyBatchX(cur realm, funds *funds, channelId types.ChannelId, path *u256.Uint, batch z.Batch) error {
	return v.verifyBatch(0, cur, funds, channelId, path, batch)
}

func (v *ucs03ZkgmV1) verifyForwardX(cur realm, funds *funds, channelId types.ChannelId, forward z.Forward) error {
	return v.verifyForward(0, cur, funds, channelId, forward)
}

func (v *ucs03ZkgmV1) verifyCallX(cur realm, call z.Call) error {
	return v.verifyCall(0, cur, call)
}

// blockNow returns the current block time as the uint256 the token bucket uses
// as its refill anchor, matching rate_limit.gno's internal time.Now().Unix().
func blockNow() *u256.Uint {
	return u256.NewUint(uint64(time.Now().Unix()))
}

// helpers_test.gno holds test fixtures shared across the per-file test suites.
// Each *_test.gno file tests only the functions of its matching implementation
// file; the construction/encoding helpers used by several of them live here.

// testStore is the in-memory IStore mock injected into the impl under test. The
// proxy keeps its real Store private (no exported getter) and its borrow-rule
// setters can only be driven from the proxy realm, so the unit tests inject this
// test-realm-owned mock instead (see mockstore_test.gno).
var testStore = newMockStore()

// newTestImpl builds a v1 impl bound to the test-owned store, the way the proxy
// injects its singleton at Register time.
func newTestImpl() *ucs03ZkgmV1 {
	return &ucs03ZkgmV1{store: testStore}
}

func testAddress(name string) address {
	return testutils.TestAddress(name)
}

// voucher read helpers: vouchers are proxy-owned state, so tests read them back
// through the store rather than a removed package-level getter.

func voucherBalanceOf(ibcDenom string, addr address) int64 {
	vou, ok := testStore.GetVoucher(ibcDenom)
	if !ok {
		return 0
	}
	return vou.Token().BalanceOf(addr)
}

func voucherNameOf(ibcDenom string) string {
	vou, ok := testStore.GetVoucher(ibcDenom)
	if !ok {
		return ""
	}
	return vou.Token().GetName()
}

func voucherSymbolOf(ibcDenom string) string {
	vou, ok := testStore.GetVoucher(ibcDenom)
	if !ok {
		return ""
	}
	return vou.Token().GetSymbol()
}

func voucherDecimalsOf(ibcDenom string) int {
	vou, ok := testStore.GetVoucher(ibcDenom)
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
