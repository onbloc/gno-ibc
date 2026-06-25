package types

import "testing"

func TestNewHeight(t *testing.T) {
	tests := []struct {
		name   string
		height uint64
		want   Height
	}{
		{
			name:   "zero height",
			height: 0,
			want:   Height{RevisionNumber: 0, RevisionHeight: 0},
		},
		{
			name:   "single height",
			height: 1,
			want:   Height{RevisionNumber: 0, RevisionHeight: 1},
		},
		{
			name:   "large height",
			height: 1000000,
			want:   Height{RevisionNumber: 0, RevisionHeight: 1000000},
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := NewHeight(0, tc.height)
			if got != tc.want {
				t.Fatalf("NewHeight(0, %v) = %v, want %v", tc.height, got, tc.want)
			}
		})
	}
}

func TestNewHeightRevisionArgs(t *testing.T) {
	tests := []struct {
		name     string
		revision uint64
		height   uint64
		want     Height
	}{
		{
			name:     "zero revision and height",
			revision: 0,
			height:   0,
			want:     Height{RevisionNumber: 0, RevisionHeight: 0},
		},
		{
			name:     "zero revision with height",
			revision: 0,
			height:   100,
			want:     Height{RevisionNumber: 0, RevisionHeight: 100},
		},
		{
			name:     "non-zero revision with zero height",
			revision: 1,
			height:   0,
			want:     Height{RevisionNumber: 1, RevisionHeight: 0},
		},
		{
			name:     "both non-zero",
			revision: 5,
			height:   100,
			want:     Height{RevisionNumber: 5, RevisionHeight: 100},
		},
		{
			name:     "large values",
			revision: 18446744073709551615,
			height:   18446744073709551615,
			want:     Height{RevisionNumber: 18446744073709551615, RevisionHeight: 18446744073709551615},
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := NewHeight(tc.revision, tc.height)
			if got != tc.want {
				t.Fatalf("NewHeight(%v, %v) = %v, want %v", tc.revision, tc.height, got, tc.want)
			}
		})
	}
}

func TestHeightIsZero(t *testing.T) {
	tests := []struct {
		name string
		h    Height
		want bool
	}{
		{
			name: "zero struct",
			h:    Height{},
			want: true,
		},
		{
			name: "zero revision and zero height",
			h:    Height{RevisionNumber: 0, RevisionHeight: 0},
			want: true,
		},
		{
			name: "zero revision with non-zero height",
			h:    Height{RevisionNumber: 0, RevisionHeight: 1},
			want: false,
		},
		{
			name: "non-zero revision with zero height",
			h:    Height{RevisionNumber: 1, RevisionHeight: 0},
			want: false,
		},
		{
			name: "both non-zero",
			h:    Height{RevisionNumber: 1, RevisionHeight: 1},
			want: false,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := tc.h.IsZero()
			if got != tc.want {
				t.Fatalf("Height{%v}.IsZero() = %v, want %v", tc.h, got, tc.want)
			}
		})
	}
}

func TestHeightHasRevision(t *testing.T) {
	tests := []struct {
		name string
		h    Height
		want bool
	}{
		{
			name: "zero struct",
			h:    Height{},
			want: false,
		},
		{
			name: "zero revision",
			h:    Height{RevisionNumber: 0, RevisionHeight: 100},
			want: false,
		},
		{
			name: "non-zero revision",
			h:    Height{RevisionNumber: 1, RevisionHeight: 0},
			want: true,
		},
		{
			name: "non-zero revision with height",
			h:    Height{RevisionNumber: 5, RevisionHeight: 100},
			want: true,
		},
		{
			name: "large revision",
			h:    Height{RevisionNumber: 18446744073709551615, RevisionHeight: 0},
			want: true,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := tc.h.HasRevision()
			if got != tc.want {
				t.Fatalf("Height{%v}.HasRevision() = %v, want %v", tc.h, got, tc.want)
			}
		})
	}
}

func TestHeightGetRevision(t *testing.T) {
	tests := []struct {
		name string
		h    Height
		want uint64
	}{
		{
			name: "zero struct",
			h:    Height{},
			want: 0,
		},
		{
			name: "zero revision",
			h:    Height{RevisionNumber: 0, RevisionHeight: 100},
			want: 0,
		},
		{
			name: "non-zero revision",
			h:    Height{RevisionNumber: 5, RevisionHeight: 100},
			want: 5,
		},
		{
			name: "max revision",
			h:    Height{RevisionNumber: 18446744073709551615, RevisionHeight: 0},
			want: 18446744073709551615,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := tc.h.GetRevision()
			if got != tc.want {
				t.Fatalf("Height{%v}.GetRevision() = %v, want %v", tc.h, got, tc.want)
			}
		})
	}
}

func TestHeightGetHeight(t *testing.T) {
	tests := []struct {
		name string
		h    Height
		want uint64
	}{
		{
			name: "zero struct",
			h:    Height{},
			want: 0,
		},
		{
			name: "zero height with revision",
			h:    Height{RevisionNumber: 5, RevisionHeight: 0},
			want: 0,
		},
		{
			name: "non-zero height",
			h:    Height{RevisionNumber: 0, RevisionHeight: 100},
			want: 100,
		},
		{
			name: "both non-zero",
			h:    Height{RevisionNumber: 5, RevisionHeight: 200},
			want: 200,
		},
		{
			name: "max height",
			h:    Height{RevisionNumber: 0, RevisionHeight: 18446744073709551615},
			want: 18446744073709551615,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := tc.h.GetHeight()
			if got != tc.want {
				t.Fatalf("Height{%v}.GetHeight() = %v, want %v", tc.h, got, tc.want)
			}
		})
	}
}

func TestHeightRevisionMatches(t *testing.T) {
	tests := []struct {
		name  string
		h     Height
		other Height
		want  bool
	}{
		{
			name:  "both zero revisions",
			h:     Height{RevisionNumber: 0, RevisionHeight: 100},
			other: Height{RevisionNumber: 0, RevisionHeight: 200},
			want:  true,
		},
		{
			name:  "first zero revision",
			h:     Height{RevisionNumber: 0, RevisionHeight: 100},
			other: Height{RevisionNumber: 5, RevisionHeight: 200},
			want:  true,
		},
		{
			name:  "second zero revision",
			h:     Height{RevisionNumber: 5, RevisionHeight: 100},
			other: Height{RevisionNumber: 0, RevisionHeight: 200},
			want:  true,
		},
		{
			name:  "same non-zero revision",
			h:     Height{RevisionNumber: 5, RevisionHeight: 100},
			other: Height{RevisionNumber: 5, RevisionHeight: 200},
			want:  true,
		},
		{
			name:  "different non-zero revisions",
			h:     Height{RevisionNumber: 5, RevisionHeight: 100},
			other: Height{RevisionNumber: 10, RevisionHeight: 200},
			want:  false,
		},
		{
			name:  "both zero struct",
			h:     Height{},
			other: Height{},
			want:  true,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := tc.h.RevisionMatches(tc.other)
			if got != tc.want {
				t.Fatalf("Height{%v}.RevisionMatches(Height{%v}) = %v, want %v", tc.h, tc.other, got, tc.want)
			}
		})
	}
}

func TestHeightIncrement(t *testing.T) {
	tests := []struct {
		name string
		h    Height
		want Height
	}{
		{
			name: "zero struct",
			h:    Height{},
			want: Height{RevisionNumber: 0, RevisionHeight: 1},
		},
		{
			name: "zero height",
			h:    Height{RevisionNumber: 5, RevisionHeight: 0},
			want: Height{RevisionNumber: 5, RevisionHeight: 1},
		},
		{
			name: "non-zero height",
			h:    Height{RevisionNumber: 0, RevisionHeight: 100},
			want: Height{RevisionNumber: 0, RevisionHeight: 101},
		},
		{
			name: "with revision",
			h:    Height{RevisionNumber: 10, RevisionHeight: 50},
			want: Height{RevisionNumber: 10, RevisionHeight: 51},
		},
		{
			name: "max height minus one",
			h:    Height{RevisionNumber: 0, RevisionHeight: 18446744073709551614},
			want: Height{RevisionNumber: 0, RevisionHeight: 18446744073709551615},
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := tc.h.Increment()
			if got != tc.want {
				t.Fatalf("Height{%v}.Increment() = %v, want %v", tc.h, got, tc.want)
			}
			// Ensure original unchanged
			if tc.h.RevisionHeight != 0 && tc.h.RevisionHeight+1 == got.RevisionHeight && tc.h.RevisionNumber != got.RevisionNumber {
				t.Fatal("Increment modified original revision number")
			}
		})
	}
}

func TestHeightIncrementBy(t *testing.T) {
	tests := []struct {
		name string
		h    Height
		n    uint64
		want Height
	}{
		{
			name: "zero by one",
			h:    Height{},
			n:    1,
			want: Height{RevisionNumber: 0, RevisionHeight: 1},
		},
		{
			name: "zero by zero",
			h:    Height{},
			n:    0,
			want: Height{RevisionNumber: 0, RevisionHeight: 0},
		},
		{
			name: "increment by one",
			h:    Height{RevisionNumber: 5, RevisionHeight: 100},
			n:    1,
			want: Height{RevisionNumber: 5, RevisionHeight: 101},
		},
		{
			name: "increment by large amount",
			h:    Height{RevisionNumber: 0, RevisionHeight: 100},
			n:    1000,
			want: Height{RevisionNumber: 0, RevisionHeight: 1100},
		},
		{
			name: "with revision",
			h:    Height{RevisionNumber: 10, RevisionHeight: 50},
			n:    25,
			want: Height{RevisionNumber: 10, RevisionHeight: 75},
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := tc.h.IncrementBy(tc.n)
			if got != tc.want {
				t.Fatalf("Height{%v}.IncrementBy(%v) = %v, want %v", tc.h, tc.n, got, tc.want)
			}
		})
	}
}

func TestHeightCmp(t *testing.T) {
	tests := []struct {
		name  string
		h     Height
		other Height
		want  int
	}{
		// Both have revisions - revision compared first
		{
			name:  "both have revisions - less revision",
			h:     Height{RevisionNumber: 5, RevisionHeight: 100},
			other: Height{RevisionNumber: 10, RevisionHeight: 0},
			want:  -1,
		},
		{
			name:  "both have revisions - greater revision",
			h:     Height{RevisionNumber: 10, RevisionHeight: 0},
			other: Height{RevisionNumber: 5, RevisionHeight: 100},
			want:  1,
		},
		{
			name:  "both have revisions - same revision less height",
			h:     Height{RevisionNumber: 5, RevisionHeight: 50},
			other: Height{RevisionNumber: 5, RevisionHeight: 100},
			want:  -1,
		},
		{
			name:  "both have revisions - same revision greater height",
			h:     Height{RevisionNumber: 5, RevisionHeight: 100},
			other: Height{RevisionNumber: 5, RevisionHeight: 50},
			want:  1,
		},
		{
			name:  "both have revisions - equal",
			h:     Height{RevisionNumber: 5, RevisionHeight: 100},
			other: Height{RevisionNumber: 5, RevisionHeight: 100},
			want:  0,
		},
		// One or both have no revision - height only
		{
			name:  "first no revision - less height",
			h:     Height{RevisionNumber: 0, RevisionHeight: 50},
			other: Height{RevisionNumber: 10, RevisionHeight: 100},
			want:  -1,
		},
		{
			name:  "second no revision - less height",
			h:     Height{RevisionNumber: 10, RevisionHeight: 50},
			other: Height{RevisionNumber: 0, RevisionHeight: 100},
			want:  -1,
		},
		{
			name:  "both no revision - less height",
			h:     Height{RevisionNumber: 0, RevisionHeight: 50},
			other: Height{RevisionNumber: 0, RevisionHeight: 100},
			want:  -1,
		},
		{
			name:  "both no revision - greater height",
			h:     Height{RevisionNumber: 0, RevisionHeight: 100},
			other: Height{RevisionNumber: 0, RevisionHeight: 50},
			want:  1,
		},
		{
			name:  "both no revision - equal",
			h:     Height{RevisionNumber: 0, RevisionHeight: 100},
			other: Height{RevisionNumber: 0, RevisionHeight: 100},
			want:  0,
		},
		{
			name:  "first no revision equal heights",
			h:     Height{RevisionNumber: 0, RevisionHeight: 100},
			other: Height{RevisionNumber: 10, RevisionHeight: 100},
			want:  0,
		},
		// Zero cases
		{
			name:  "zero struct vs non-zero",
			h:     Height{},
			other: Height{RevisionNumber: 0, RevisionHeight: 1},
			want:  -1,
		},
		{
			name:  "non-zero vs zero struct",
			h:     Height{RevisionNumber: 0, RevisionHeight: 1},
			other: Height{},
			want:  1,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := tc.h.Cmp(tc.other)
			if got != tc.want {
				t.Fatalf("Height{%v}.Cmp(Height{%v}) = %v, want %v", tc.h, tc.other, got, tc.want)
			}
		})
	}
}

func TestHeightLT(t *testing.T) {
	tests := []struct {
		name  string
		h     Height
		other Height
		want  bool
	}{
		{
			name:  "less height, no revision",
			h:     Height{RevisionNumber: 0, RevisionHeight: 50},
			other: Height{RevisionNumber: 0, RevisionHeight: 100},
			want:  true,
		},
		{
			name:  "equal height, no revision",
			h:     Height{RevisionNumber: 0, RevisionHeight: 100},
			other: Height{RevisionNumber: 0, RevisionHeight: 100},
			want:  false,
		},
		{
			name:  "greater height, no revision",
			h:     Height{RevisionNumber: 0, RevisionHeight: 100},
			other: Height{RevisionNumber: 0, RevisionHeight: 50},
			want:  false,
		},
		{
			name:  "less revision",
			h:     Height{RevisionNumber: 5, RevisionHeight: 100},
			other: Height{RevisionNumber: 10, RevisionHeight: 0},
			want:  true,
		},
		{
			name:  "same revision, less height",
			h:     Height{RevisionNumber: 5, RevisionHeight: 50},
			other: Height{RevisionNumber: 5, RevisionHeight: 100},
			want:  true,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := tc.h.LT(tc.other)
			if got != tc.want {
				t.Fatalf("Height{%v}.LT(Height{%v}) = %v, want %v", tc.h, tc.other, got, tc.want)
			}
		})
	}
}

func TestHeightLTE(t *testing.T) {
	tests := []struct {
		name  string
		h     Height
		other Height
		want  bool
	}{
		{
			name:  "less height, no revision",
			h:     Height{RevisionNumber: 0, RevisionHeight: 50},
			other: Height{RevisionNumber: 0, RevisionHeight: 100},
			want:  true,
		},
		{
			name:  "equal height, no revision",
			h:     Height{RevisionNumber: 0, RevisionHeight: 100},
			other: Height{RevisionNumber: 0, RevisionHeight: 100},
			want:  true,
		},
		{
			name:  "greater height, no revision",
			h:     Height{RevisionNumber: 0, RevisionHeight: 100},
			other: Height{RevisionNumber: 0, RevisionHeight: 50},
			want:  false,
		},
		{
			name:  "same revision, equal height",
			h:     Height{RevisionNumber: 5, RevisionHeight: 100},
			other: Height{RevisionNumber: 5, RevisionHeight: 100},
			want:  true,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := tc.h.LTE(tc.other)
			if got != tc.want {
				t.Fatalf("Height{%v}.LTE(Height{%v}) = %v, want %v", tc.h, tc.other, got, tc.want)
			}
		})
	}
}

func TestHeightGT(t *testing.T) {
	tests := []struct {
		name  string
		h     Height
		other Height
		want  bool
	}{
		{
			name:  "greater height, no revision",
			h:     Height{RevisionNumber: 0, RevisionHeight: 100},
			other: Height{RevisionNumber: 0, RevisionHeight: 50},
			want:  true,
		},
		{
			name:  "equal height, no revision",
			h:     Height{RevisionNumber: 0, RevisionHeight: 100},
			other: Height{RevisionNumber: 0, RevisionHeight: 100},
			want:  false,
		},
		{
			name:  "less height, no revision",
			h:     Height{RevisionNumber: 0, RevisionHeight: 50},
			other: Height{RevisionNumber: 0, RevisionHeight: 100},
			want:  false,
		},
		{
			name:  "greater revision",
			h:     Height{RevisionNumber: 10, RevisionHeight: 0},
			other: Height{RevisionNumber: 5, RevisionHeight: 100},
			want:  true,
		},
		{
			name:  "same revision, greater height",
			h:     Height{RevisionNumber: 5, RevisionHeight: 100},
			other: Height{RevisionNumber: 5, RevisionHeight: 50},
			want:  true,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := tc.h.GT(tc.other)
			if got != tc.want {
				t.Fatalf("Height{%v}.GT(Height{%v}) = %v, want %v", tc.h, tc.other, got, tc.want)
			}
		})
	}
}

func TestHeightGTE(t *testing.T) {
	tests := []struct {
		name  string
		h     Height
		other Height
		want  bool
	}{
		{
			name:  "greater height, no revision",
			h:     Height{RevisionNumber: 0, RevisionHeight: 100},
			other: Height{RevisionNumber: 0, RevisionHeight: 50},
			want:  true,
		},
		{
			name:  "equal height, no revision",
			h:     Height{RevisionNumber: 0, RevisionHeight: 100},
			other: Height{RevisionNumber: 0, RevisionHeight: 100},
			want:  true,
		},
		{
			name:  "less height, no revision",
			h:     Height{RevisionNumber: 0, RevisionHeight: 50},
			other: Height{RevisionNumber: 0, RevisionHeight: 100},
			want:  false,
		},
		{
			name:  "same revision, equal height",
			h:     Height{RevisionNumber: 5, RevisionHeight: 100},
			other: Height{RevisionNumber: 5, RevisionHeight: 100},
			want:  true,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := tc.h.GTE(tc.other)
			if got != tc.want {
				t.Fatalf("Height{%v}.GTE(Height{%v}) = %v, want %v", tc.h, tc.other, got, tc.want)
			}
		})
	}
}

func TestHeightEQ(t *testing.T) {
	tests := []struct {
		name  string
		h     Height
		other Height
		want  bool
	}{
		{
			name:  "equal no revision",
			h:     Height{RevisionNumber: 0, RevisionHeight: 100},
			other: Height{RevisionNumber: 0, RevisionHeight: 100},
			want:  true,
		},
		{
			name:  "equal with revision",
			h:     Height{RevisionNumber: 5, RevisionHeight: 100},
			other: Height{RevisionNumber: 5, RevisionHeight: 100},
			want:  true,
		},
		{
			name:  "different height, same revision",
			h:     Height{RevisionNumber: 5, RevisionHeight: 100},
			other: Height{RevisionNumber: 5, RevisionHeight: 50},
			want:  false,
		},
		{
			name:  "different revision, same height",
			h:     Height{RevisionNumber: 5, RevisionHeight: 100},
			other: Height{RevisionNumber: 10, RevisionHeight: 100},
			want:  false,
		},
		{
			name:  "both zero",
			h:     Height{},
			other: Height{},
			want:  true,
		},
		{
			name:  "zero vs non-zero",
			h:     Height{},
			other: Height{RevisionNumber: 0, RevisionHeight: 1},
			want:  false,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := tc.h.EQ(tc.other)
			if got != tc.want {
				t.Fatalf("Height{%v}.EQ(Height{%v}) = %v, want %v", tc.h, tc.other, got, tc.want)
			}
		})
	}
}

func TestHeightString(t *testing.T) {
	tests := []struct {
		name string
		h    Height
		want string
	}{
		{
			name: "zero height no revision",
			h:    Height{RevisionNumber: 0, RevisionHeight: 0},
			want: "0",
		},
		{
			name: "height only",
			h:    Height{RevisionNumber: 0, RevisionHeight: 100},
			want: "100",
		},
		{
			name: "revision with zero height",
			h:    Height{RevisionNumber: 5, RevisionHeight: 0},
			want: "5-0",
		},
		{
			name: "revision and height",
			h:    Height{RevisionNumber: 5, RevisionHeight: 100},
			want: "5-100",
		},
		{
			name: "large revision and height",
			h:    Height{RevisionNumber: 18446744073709551615, RevisionHeight: 18446744073709551615},
			want: "18446744073709551615-18446744073709551615",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := tc.h.String()
			if got != tc.want {
				t.Fatalf("Height{%v}.String() = %q, want %q", tc.h, got, tc.want)
			}
		})
	}
}

func TestHeightBytes(t *testing.T) {
	tests := []struct {
		name string
		h    Height
		want []byte
	}{
		{
			name: "zero height",
			h:    Height{RevisionNumber: 0, RevisionHeight: 0},
			want: []byte{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
		},
		{
			name: "height only",
			h:    Height{RevisionNumber: 0, RevisionHeight: 1},
			want: []byte{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1},
		},
		{
			name: "revision only",
			h:    Height{RevisionNumber: 1, RevisionHeight: 0},
			want: []byte{0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0},
		},
		{
			name: "revision and height",
			h:    Height{RevisionNumber: 5, RevisionHeight: 100},
			want: []byte{0, 0, 0, 0, 0, 0, 0, 5, 0, 0, 0, 0, 0, 0, 0, 100},
		},
		{
			name: "large values",
			h:    Height{RevisionNumber: 255, RevisionHeight: 256},
			want: []byte{0, 0, 0, 0, 0, 0, 0, 255, 0, 0, 0, 0, 0, 0, 1, 0},
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := tc.h.Bytes()
			if len(got) != len(tc.want) {
				t.Fatalf("Height{%v}.Bytes() length = %d, want %d", tc.h, len(got), len(tc.want))
			}
			for i := range got {
				if got[i] != tc.want[i] {
					t.Fatalf("Height{%v}.Bytes()[%d] = %d, want %d", tc.h, i, got[i], tc.want[i])
				}
			}
		})
	}
}

func TestParseHeight(t *testing.T) {
	tests := []struct {
		name    string
		s       string
		want    Height
		wantErr bool
	}{
		{
			name:    "empty string",
			s:       "",
			want:    Height{},
			wantErr: true,
		},
		{
			name:    "bare height zero",
			s:       "0",
			want:    Height{RevisionNumber: 0, RevisionHeight: 0},
			wantErr: false,
		},
		{
			name:    "bare height",
			s:       "100",
			want:    Height{RevisionNumber: 0, RevisionHeight: 100},
			wantErr: false,
		},
		{
			name:    "revision-height with zero revision",
			s:       "0-100",
			want:    Height{RevisionNumber: 0, RevisionHeight: 100},
			wantErr: false,
		},
		{
			name:    "revision-height with zero height",
			s:       "5-0",
			want:    Height{RevisionNumber: 5, RevisionHeight: 0},
			wantErr: false,
		},
		{
			name:    "revision-height",
			s:       "5-100",
			want:    Height{RevisionNumber: 5, RevisionHeight: 100},
			wantErr: false,
		},
		{
			name:    "large revision-height",
			s:       "18446744073709551615-18446744073709551615",
			want:    Height{RevisionNumber: 18446744073709551615, RevisionHeight: 18446744073709551615},
			wantErr: false,
		},
		{
			name:    "invalid height string",
			s:       "abc",
			want:    Height{},
			wantErr: true,
		},
		{
			name:    "invalid revision",
			s:       "abc-100",
			want:    Height{},
			wantErr: true,
		},
		{
			name:    "invalid height in revision-height",
			s:       "5-abc",
			want:    Height{},
			wantErr: true,
		},
		{
			name:    "negative number",
			s:       "-1",
			want:    Height{},
			wantErr: true,
		},
		{
			name:    "multiple dashes - invalid",
			s:       "5-100-200",
			want:    Height{},
			wantErr: true,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got, err := ParseHeight(tc.s)
			if tc.wantErr {
				if err == nil {
					t.Fatalf("ParseHeight(%q) expected error, got nil", tc.s)
				}
				return
			}
			if err != nil {
				t.Fatalf("ParseHeight(%q) unexpected error: %v", tc.s, err)
			}
			if got != tc.want {
				t.Fatalf("ParseHeight(%q) = %v, want %v", tc.s, got, tc.want)
			}
		})
	}
}
