package manager

import "testing"

func TestNewTimepoint(t *testing.T) {
	if NewTimepoint(42) != Timepoint(42) {
		t.Fatal("NewTimepoint must preserve the provided value")
	}
}

func TestCurrentTimepointIsPositive(t *testing.T) {
	if CurrentTimepoint() <= 0 {
		t.Fatal("CurrentTimepoint must return a positive unix timestamp")
	}
}

func TestTimepointAvailableAtWithoutDelay(t *testing.T) {
	if NewTimepoint(100).availableAt(0) != NewTimepoint(100) {
		t.Fatal("availableAt without delay must return the current timepoint")
	}
}

func TestTimepointAvailableAtAddsDelay(t *testing.T) {
	if NewTimepoint(100).availableAt(NewDelay(10)) != NewTimepoint(110) {
		t.Fatal("availableAt must add grant delay")
	}
}

func TestTimepointAvailableAtNeverReturnsZero(t *testing.T) {
	if NewTimepoint(-1).availableAt(NewDelay(1)) != NewTimepoint(1) {
		t.Fatal("availableAt must preserve zero as the inactive sentinel")
	}
}
