package ucs03_zkgm

import (
	"errors"

	z "gno.land/p/onbloc/ibc/union/zkgm"
)

// mock_forward_handler_test.gno is a recording z.TokenForwardHandler used by the
// token-order forward dispatch tests, mirroring mock_receiver_test.gno.

type mockForwardHandler struct {
	prepareCalls int
	executeCalls int
	lastReq      z.TokenForwardRequest
	lastCorrID   string
	prepareErr   string
}

var mockFwd = &mockForwardHandler{}

var _ z.TokenForwardHandler = (*mockForwardHandler)(nil)

func ResetForwardHandler(cur realm) {
	mockFwd.prepareCalls = 0
	mockFwd.executeCalls = 0
	mockFwd.lastReq = z.TokenForwardRequest{}
	mockFwd.lastCorrID = ""
	mockFwd.prepareErr = ""
}

func SetForwardPrepareErr(cur realm, msg string) { mockFwd.prepareErr = msg }
func ForwardPrepareCalls(cur realm) int          { return mockFwd.prepareCalls }
func ForwardExecuteCalls(cur realm) int          { return mockFwd.executeCalls }
func LastForwardCorrID(cur realm) string         { return mockFwd.lastCorrID }
func LastForwardMemo(cur realm) string           { return string(mockFwd.lastReq.Memo) }
func LastForwardBaseTokenKey(cur realm) string   { return mockFwd.lastReq.BaseTokenKey }
func LastForwardAmount(cur realm) int64          { return mockFwd.lastReq.Amount }

func (r *mockForwardHandler) Prepare(cur realm, req z.TokenForwardRequest, corrID string) error {
	r.prepareCalls++
	r.lastReq = req
	r.lastCorrID = corrID

	if r.prepareErr != "" {
		return errors.New(r.prepareErr)
	}
	return nil
}

func (r *mockForwardHandler) Execute(cur realm, req z.TokenForwardRequest, corrID string) {
	r.executeCalls++
	r.lastReq = req
	r.lastCorrID = corrID
}

// mockDeployableForwardHandler additionally implements z.TokenForwardMetadataResolver.
type mockDeployableForwardHandler struct {
	mockForwardHandler

	resolveMetadata z.TokenMetadata
	resolveHasMeta  bool
	resolveErr      string
}

var mockDeployFwd = &mockDeployableForwardHandler{}

var _ z.TokenForwardHandler = (*mockDeployableForwardHandler)(nil)
var _ z.TokenForwardMetadataResolver = (*mockDeployableForwardHandler)(nil)

func ResetDeployForwardHandler(cur realm) {
	mockDeployFwd.prepareCalls = 0
	mockDeployFwd.executeCalls = 0
	mockDeployFwd.lastReq = z.TokenForwardRequest{}
	mockDeployFwd.lastCorrID = ""
	mockDeployFwd.prepareErr = ""
	mockDeployFwd.resolveMetadata = z.TokenMetadata{}
	mockDeployFwd.resolveHasMeta = false
	mockDeployFwd.resolveErr = ""
}

func SetDeployResolveMetadata(cur realm, metadata z.TokenMetadata) {
	mockDeployFwd.resolveMetadata = metadata
	mockDeployFwd.resolveHasMeta = true
}

func SetDeployResolveErr(cur realm, msg string) { mockDeployFwd.resolveErr = msg }

func DeployForwardPrepareCalls(cur realm) int      { return mockDeployFwd.prepareCalls }
func DeployForwardExecuteCalls(cur realm) int      { return mockDeployFwd.executeCalls }
func LastDeployForwardBaseTokenKey(cur realm) string { return mockDeployFwd.lastReq.BaseTokenKey }
func LastDeployForwardAmount(cur realm) int64        { return mockDeployFwd.lastReq.Amount }

func (r *mockDeployableForwardHandler) ResolveMetadata(memo []byte) (z.TokenMetadata, bool, error) {
	if r.resolveErr != "" {
		return z.TokenMetadata{}, false, errors.New(r.resolveErr)
	}
	return r.resolveMetadata, r.resolveHasMeta, nil
}
