package manager

import "testing"

func TestNewTimepoint(t *testing.T) {
	if NewTimepoint(42).Unix() != 42 {
		t.Fatal("NewTimepoint must preserve the provided unix timestamp")
	}
}

func TestCurrentTimepointIsPositive(t *testing.T) {
	if CurrentTimepoint().Unix() <= 0 {
		t.Fatal("CurrentTimepoint must return a positive unix timestamp")
	}
}

func TestTimepointAvailableAtWithoutDelay(t *testing.T) {
	if !timepointAvailableAt(NewTimepoint(100), 0).Equal(NewTimepoint(100)) {
		t.Fatal("availableAt without delay must return the current timepoint")
	}
}

func TestTimepointAvailableAtAddsDelay(t *testing.T) {
	if !timepointAvailableAt(NewTimepoint(100), NewDelay(10)).Equal(NewTimepoint(110)) {
		t.Fatal("availableAt must add grant delay")
	}
}

func TestTimepointAvailableAtPreservesZeroTimepoint(t *testing.T) {
	var zero Timepoint
	if !timepointAvailableAt(zero, NewDelay(1)).IsZero() {
		t.Fatal("availableAt must preserve zero time as the inactive sentinel")
	}
}
