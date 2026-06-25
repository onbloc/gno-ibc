package manager

import "testing"

func TestAccessIsActiveAt(t *testing.T) {
	now := NewTimePoint(100)

	tests := []struct {
		name   string
		access Access
		want   bool
	}{
		{"zero", Access{}, false},
		{"future", NewAccess(NewTimePoint(101), 0, 0), false},
		{"current", NewAccess(now, 0, 0), true},
		{"past", NewAccess(NewTimePoint(99), 0, 0), true},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			if got := tc.access.isActiveAt(now); got != tc.want {
				t.Fatalf("isActiveAt() = %v, want %v", got, tc.want)
			}
		})
	}
}
