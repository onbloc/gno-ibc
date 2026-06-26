package attr

import (
	"strconv"
	"testing"
)

func TestColumnsBoundary(cur realm, t *testing.T) {
	testCases := []struct {
		name     string
		value    string
		wantLens []int
	}{
		{"empty value", "", []int{0}},
		{"one column", fixedValue(MaxValueLen()), []int{MaxValueLen()}},
		{"two columns", fixedValue(MaxValueLen()+1), []int{MaxValueLen(), 1}},
		{"three columns", fixedValue(MaxValueLen()*2+1), []int{MaxValueLen(), MaxValueLen(), 1}},
		{"four columns", fixedValue(MaxValueLen()*3+1), []int{MaxValueLen(), MaxValueLen(), MaxValueLen(), 1}},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			attrs := Columns("attr", tc.value)
			assertColumns(t, attrs, "attr", tc.value, tc.wantLens)
		})
	}
}

func assertColumns(t *testing.T, attrs []string, key string, value string, wantLens []int) {
	t.Helper()

	if len(attrs) != len(wantLens)*2 {
		t.Fatalf("attr len: got %d want %d attrs=%v", len(attrs), len(wantLens)*2, attrs)
	}

	rejoined := ""
	for i, wantLen := range wantLens {
		keyIndex := i * 2
		valueIndex := keyIndex + 1
		wantKey := key + "[" + strconv.Itoa(i) + "]"
		if attrs[keyIndex] != wantKey {
			t.Fatalf("attr key[%d]: got %q want %q", i, attrs[keyIndex], wantKey)
		}
		if len(attrs[valueIndex]) != wantLen {
			t.Fatalf("attr value[%d] len: got %d want %d", i, len(attrs[valueIndex]), wantLen)
		}
		if len(attrs[valueIndex]) > MaxValueLen() {
			t.Fatalf("attr value[%d] len exceeds max: got %d want <= %d", i, len(attrs[valueIndex]), MaxValueLen())
		}
		rejoined += attrs[valueIndex]
	}
	if rejoined != value {
		t.Fatalf("rejoined attr value: got %q want %q", rejoined, value)
	}
}

func fixedValue(size int) string {
	value := ""
	for len(value) < size {
		value += "0123456789abcdef"
	}
	return value[:size]
}
