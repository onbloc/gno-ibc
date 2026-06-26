package attr

import (
	"strconv"
	"testing"
)

const testMaxValueLen = 1024

func TestColumnsBoundary(cur realm, t *testing.T) {
	testCases := []struct {
		name        string
		value       string
		maxValueLen int
		want        []string
		wantLens    []int
	}{
		{"non-positive max returns unsplit value", "abcd", 0, []string{"attr", "abcd"}, nil},
		{"empty value", "", testMaxValueLen, nil, []int{0}},
		{"one column", fixedValue(testMaxValueLen), testMaxValueLen, nil, []int{testMaxValueLen}},
		{"two columns", fixedValue(testMaxValueLen+1), testMaxValueLen, nil, []int{testMaxValueLen, 1}},
		{"three columns", fixedValue(testMaxValueLen*2+1), testMaxValueLen, nil, []int{testMaxValueLen, testMaxValueLen, 1}},
		{"four columns", fixedValue(testMaxValueLen*3+1), testMaxValueLen, nil, []int{testMaxValueLen, testMaxValueLen, testMaxValueLen, 1}},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			attrs := Columns("attr", tc.value, tc.maxValueLen)
			if tc.want != nil {
				assertAttrs(t, attrs, tc.want)
				return
			}
			assertColumns(t, attrs, "attr", tc.value, tc.wantLens)
		})
	}
}

func assertAttrs(t *testing.T, got []string, want []string) {
	t.Helper()

	if len(got) != len(want) {
		t.Fatalf("attrs len: got %d want %d attrs=%v", len(got), len(want), got)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("attrs[%d]: got %q want %q attrs=%v", i, got[i], want[i], got)
		}
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
		if len(attrs[valueIndex]) > testMaxValueLen {
			t.Fatalf("attr value[%d] len exceeds max: got %d want <= %d", i, len(attrs[valueIndex]), testMaxValueLen)
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
