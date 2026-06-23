package manager

import "testing"

func TestAccessIsActiveAt(t *testing.T) {
	now := NewTimepoint(100)

	tests := []struct {
		name   string
		access Access
		want   bool
	}{
		{"zero", Access{}, false},
		{"future", NewAccess(NewTimepoint(101)), false},
		{"current", NewAccess(now), true},
		{"past", NewAccess(NewTimepoint(99)), true},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			if got := tc.access.isActiveAt(now); got != tc.want {
				t.Fatalf("isActiveAt() = %v, want %v", got, tc.want)
			}
		})
	}
}
