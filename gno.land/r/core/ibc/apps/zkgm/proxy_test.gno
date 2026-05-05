package zkgm

import (
	"errors"
	"testing"

	"gno.land/p/aib/ibc/types"
	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/bptree/v0"
)

const (
	v0Impl  = "gno.land/r/gnoswap/ibc/apps/zkgm/v0/impl"
	v1Impl  = "gno.land/r/gnoswap/ibc/apps/zkgm/v1/impl"
	invalid = "gno.land/r/gnoswap/ibc/apps/zkgm/invalid"
)

func TestProxyBootstrapAllowedEmpty(cur realm, t *testing.T) {
	resetProxyForTest()

	testing.SetRealm(testing.NewCodeRealm(invalid))
	UpdateImpl(cross, UpdateRequest{Impl: &dummyImpl{name: "boot"}})

	if ImplPath() != invalid {
		t.Fatalf("impl path: got %q want %q", ImplPath(), invalid)
	}
	if len(AllowedImpls()) != 0 {
		t.Fatalf("bootstrap should leave allowed impls empty")
	}
}

func TestProxyUpdateImplDeniedAfterLock(cur realm, t *testing.T) {
	resetProxyForTest()
	lockToV0()

	testing.SetRealm(testing.NewCodeRealm(invalid))
	expectAbort(t, "permission denied for prev realm: "+invalid, func() {
		UpdateImpl(cross, UpdateRequest{Impl: &dummyImpl{name: "bad"}})
	})
}

func TestProxyUpdateImplSelfRegister(cur realm, t *testing.T) {
	resetProxyForTest()
	lockToV0()

	testing.SetRealm(testing.NewCodeRealm(v0Impl))
	UpdateImpl(cross, UpdateRequest{Impl: &dummyImpl{name: "v0b"}})

	if ImplPath() != v0Impl {
		t.Fatalf("impl path: got %q want %q", ImplPath(), v0Impl)
	}
}

func TestProxyUpdateImplMultiVersionRollback(cur realm, t *testing.T) {
	resetProxyForTest()
	lockToV0()

	testing.SetRealm(testing.NewCodeRealm(v0Impl))
	UpdateImpl(cross, UpdateRequest{
		Impl:         &dummyImpl{name: "v1"},
		AllowedImpls: []string{v0Impl, v1Impl},
	})
	if len(AllowedImpls()) != 2 {
		t.Fatalf("allowed impl count mismatch")
	}

	testing.SetRealm(testing.NewCodeRealm(v0Impl))
	UpdateImpl(cross, UpdateRequest{Impl: &dummyImpl{name: "v0-rollback"}})
	if ImplPath() != v0Impl {
		t.Fatalf("rollback impl path mismatch")
	}
}

func TestProxyUpdateImplSelfRemoveLosesPermission(cur realm, t *testing.T) {
	resetProxyForTest()
	lockToV0()

	testing.SetRealm(testing.NewCodeRealm(v0Impl))
	UpdateImpl(cross, UpdateRequest{AllowedImpls: []string{v1Impl}})

	testing.SetRealm(testing.NewCodeRealm(v0Impl))
	expectAbort(t, "permission denied for prev realm: "+v0Impl, func() {
		UpdateImpl(cross, UpdateRequest{Impl: &dummyImpl{name: "v0"}})
	})
}

func TestProxyLedgerSurvivesImplSwap(cur realm, t *testing.T) {
	resetProxyForTest()
	lockToV0()

	testing.SetRealm(testing.NewCodeRealm(v0Impl))
	SetTokenOrigin(cross, "denom", u256.NewUint(7))

	UpdateImpl(cross, UpdateRequest{
		Impl:         &dummyImpl{name: "v1"},
		AllowedImpls: []string{v0Impl, v1Impl},
	})

	path, ok := GetTokenOrigin("denom")
	if !ok || path.ToString() != "7" {
		t.Fatalf("token origin was not preserved")
	}
}

func TestAppRecvErrorAckWhenPaused(cur realm, t *testing.T) {
	resetProxyForTest()
	paused = true

	res := (&App{}).OnRecvPacket(cross, "client-0", "client-1", 1, types.Payload{Value: []byte("packet")})
	if res.Status != types.PacketStatus_Failure || len(res.Acknowledgement) == 0 {
		t.Fatalf("expected failure acknowledgement")
	}
}

func resetProxyForTest() {
	impl = nil
	implPath = ""
	allowedImpls = nil
	paused = false
	adminAddressStr = ""
	rateLimitDisabled = false
	tokenOrigin = bptreeNew()
	metadataImageOf = bptreeNew()
	hashToForeignToken = bptreeNew()
	channelBalanceV2 = bptreeNew()
	inFlightPacket = bptreeNew()
	tokenBucket = bptreeNew()
}

func bptreeNew() *bptree.BPTree {
	return bptree.NewBPTree32()
}

func lockToV0() {
	testing.SetRealm(testing.NewCodeRealm(v0Impl))
	UpdateImpl(cross, UpdateRequest{
		Impl:         &dummyImpl{name: "v0"},
		AllowedImpls: []string{v0Impl},
	})
}

func expectAbort(t *testing.T, want string, fn func()) {
	r := revive(fn)
	if r == nil {
		t.Fatalf("expected abort %q", want)
	}
	got := r.(string)
	if got != want {
		t.Fatalf("abort: got %q want %q", got, want)
	}
}

type dummyImpl struct {
	name string
}

func (d *dummyImpl) PreSend(req SendRequest) error {
	return nil
}

func (d *dummyImpl) Send(req SendRequest) (SendResult, error) {
	return SendResult{PacketSequence: 1}, nil
}

func (d *dummyImpl) PostSend(req SendRequest, res SendResult) {
}

func (d *dummyImpl) PreRecv(req RecvRequest) error {
	if d.name == "recv-error" {
		return errors.New("recv-error")
	}
	return nil
}

func (d *dummyImpl) Recv(req RecvRequest) (types.RecvPacketResult, error) {
	return types.RecvPacketResult{
		Status:          types.PacketStatus_Success,
		Acknowledgement: []byte("ok"),
	}, nil
}

func (d *dummyImpl) PostRecv(req RecvRequest, res types.RecvPacketResult) {
}

func (d *dummyImpl) PreAck(req AckRequest) error {
	return nil
}

func (d *dummyImpl) Ack(req AckRequest) error {
	return nil
}

func (d *dummyImpl) PostAck(req AckRequest) {
}

func (d *dummyImpl) PreTimeout(req TimeoutRequest) error {
	return nil
}

func (d *dummyImpl) Timeout(req TimeoutRequest) error {
	return nil
}

func (d *dummyImpl) PostTimeout(req TimeoutRequest) {
}

func (d *dummyImpl) Render(pkgpath string, path string) string {
	return d.name + ":" + pkgpath + "/" + path
}
