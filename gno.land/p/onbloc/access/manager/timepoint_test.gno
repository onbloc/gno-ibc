package manager

import "testing"

func TestNewTimePoint(t *testing.T) {
	tests := []struct {
		name string
		unix int64
	}{
		{"zero", 0},
		{"positive", 42},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			if got := NewTimePoint(tc.unix); int64(got) != tc.unix {
				t.Fatalf("NewTimePoint().Unix() = %d, want %d", got, tc.unix)
			}
		})
	}
}

func TestCurrentTimePointIsPositive(t *testing.T) {
	if CurrentTimePoint() <= 0 {
		t.Fatal("CurrentTimePoint must return a positive unix timestamp")
	}
}
