package impl

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func TestNewCoreV1(t *testing.T) {
	s := newMockStore()
	got := NewCoreV1(s)
	impl, ok := got.(*coreV1)

	uassert.Equal(t, true, ok)
	uassert.Equal(t, true, impl != nil)
	uassert.Equal(t, true, impl.store == s)
}

func TestResolveRelayer(t *testing.T) {
	caller := address("g1caller")

	tests := []struct {
		name    string
		relayer string
		want    address
	}{
		{"empty relayer defaults to caller", "", caller},
		{"explicit relayer wins", "g1relayer", address("g1relayer")},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			uassert.Equal(t, tc.want.String(), resolveRelayer(caller, tc.relayer).String())
		})
	}
}

func TestCloneBytes(t *testing.T) {
	tests := []struct {
		name string
		in   []byte
	}{
		{"nil", nil},
		{"empty", []byte{}},
		{"non-empty", []byte("abc")},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := cloneBytes(tc.in)
			uassert.Equal(t, len(tc.in), len(got))
			uassert.Equal(t, string(tc.in), string(got))

			if len(tc.in) != 0 {
				got[0] = 'z'
				uassert.Equal(t, "abc", string(tc.in))
			}
		})
	}
}
