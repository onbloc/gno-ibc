package manager

import "testing"

func TestAccessIsActiveAt(t *testing.T) {
	var inactive Access
	now := NewTimepoint(100)

	if inactive.isActiveAt(now) {
		t.Fatal("zero access must be inactive")
	}
	if NewAccess(NewTimepoint(101)).isActiveAt(now) {
		t.Fatal("future access must be inactive")
	}
	if !NewAccess(now).isActiveAt(now) {
		t.Fatal("access at current timepoint must be active")
	}
	if !NewAccess(NewTimepoint(99)).isActiveAt(now) {
		t.Fatal("past access must be active")
	}
}
