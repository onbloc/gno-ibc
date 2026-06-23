package manager

import "testing"

func TestTargetConfigManagesNilFunctionRolesMap(t *testing.T) {
	targetConfig := &TargetConfig{}

	if targetConfig.functionRole("unset") != AdminRole {
		t.Fatal("unset selector must default to admin role")
	}
	if targetConfig.FunctionRoles == nil {
		t.Fatal("functionRole must initialize function roles map")
	}

	targetConfig.setFunctionRole("a", testRole)
	targetConfig.setFunctionRoles([]Selector{"b", "c"}, 2)

	tests := []struct {
		name     string
		selector Selector
		want     RoleId
	}{
		{"single selector", "a", testRole},
		{"first batch selector", "b", 2},
		{"second batch selector", "c", 2},
		{"unknown selector", "unknown", AdminRole},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			if got := targetConfig.functionRole(tc.selector); got != tc.want {
				t.Fatalf("functionRole() = %d, want %d", got, tc.want)
			}
		})
	}
}

func TestTargetConfigClosed(t *testing.T) {
	tests := []struct {
		name    string
		initial bool
		next    bool
	}{
		{"open to closed", false, true},
		{"closed to open", true, false},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			targetConfig := NewTargetConfig(tc.initial)
			if got := targetConfig.isClosed(); got != tc.initial {
				t.Fatalf("initial isClosed() = %v, want %v", got, tc.initial)
			}

			targetConfig.setClosed(tc.next)
			if got := targetConfig.isClosed(); got != tc.next {
				t.Fatalf("updated isClosed() = %v, want %v", got, tc.next)
			}
		})
	}
}
