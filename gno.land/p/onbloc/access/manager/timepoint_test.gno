package manager

import "testing"

func TestNewTimepoint(t *testing.T) {
	tests := []struct {
		name string
		unix int64
	}{
		{"zero", 0},
		{"positive", 42},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			if got := NewTimepoint(tc.unix).Unix(); got != tc.unix {
				t.Fatalf("NewTimepoint().Unix() = %d, want %d", got, tc.unix)
			}
		})
	}
}

func TestCurrentTimepointIsPositive(t *testing.T) {
	if CurrentTimepoint().Unix() <= 0 {
		t.Fatal("CurrentTimepoint must return a positive unix timestamp")
	}
}

func TestTimepointAvailableAt(t *testing.T) {
	tests := []struct {
		name  string
		now   Timepoint
		delay Delay
		want  Timepoint
	}{
		{"without delay", NewTimepoint(100), 0, NewTimepoint(100)},
		{"adds delay", NewTimepoint(100), NewDelay(10), NewTimepoint(110)},
		{"preserves zero", Timepoint{}, NewDelay(1), Timepoint{}},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			if got := timepointAvailableAt(tc.now, tc.delay); !got.Equal(tc.want) {
				t.Fatalf("timepointAvailableAt() = %v, want %v", got, tc.want)
			}
		})
	}
}
